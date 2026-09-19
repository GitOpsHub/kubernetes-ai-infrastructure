"""Chapter 19 - LoRA supervised fine-tuning (TRL SFTTrainer) that survives spot loss.

Runs as the `finetune` step of the `hf-finetune-pipeline` Argo WorkflowTemplate:
    python /app/finetune.py

Env
  BASE_MODEL_PATH  (required) model dir from hf_pull.py: .../hf/models/<id>/<rev>
  DATASET_PATH     (required) dataset dir from hf_pull.py; reads data/train-*.parquet
  RUN_DIR          (required) /mnt/store/runs/<RUN_ID> on the bucket mount
  SCRATCH          local emptyDir (default /scratch)
  MAX_STEPS 200  SAVE_STEPS 50  LEARNING_RATE 2e-4  MAX_LENGTH 1024
  PER_DEVICE_BATCH 4  GRAD_ACCUM 4  LORA_R 16  TRAIN_SAMPLES 2000

Spot-preemption design
  * Trainer writes checkpoints to local scratch (it needs a real filesystem), and a
    callback copies each new checkpoint-N into $RUN_DIR/checkpoints/checkpoint-N/ as
    new files, then writes _COMPLETE. Only marked checkpoints are resume points.
  * On start, the newest complete checkpoint is copied back to scratch and training
    resumes from it: optimizer, LR scheduler, RNG and data position all come back.
  * SIGTERM (spot reclaim warning, pod deletion) sets a flag; the callback then asks
    Trainer to save at the end of the current step and stop, and we exit 143 so Argo's
    retryStrategy reschedules the step instead of marking it Succeeded.
  * $RUN_DIR/model/_COMPLETE means an earlier attempt already finished: exit 0, so a
    retried workflow does not retrain. If the newest checkpoint already reached
    MAX_STEPS (the pod died while uploading the merged model), training is skipped
    and that checkpoint is merged directly - Trainer itself would run one extra step
    when resumed at max_steps.
  * The merge is always "fresh base + final checkpoint's adapter, on CPU in fp32", on
    both paths. That makes it reproducible byte for byte, so a retry after a partial
    model/ upload finds identical files already there instead of conflicting ones
    it cannot overwrite.

Output: $RUN_DIR/model/ - the LoRA adapter merged into the base weights (safetensors,
in the base model's own dtype) plus tokenizer, so vLLM can serve it as a plain model.
"""

import os
import shutil
import signal
import sys
from pathlib import Path

import torch
from datasets import load_dataset
from peft import LoraConfig, PeftModel
from store import (
    copy_tree_new_files,
    is_complete,
    latest_complete_checkpoint,
    mark_complete,
)
from transformers import (
    AutoConfig,
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainerCallback,
    TrainerControl,
    TrainerState,
    TrainingArguments,
)
from trl import SFTConfig, SFTTrainer

# ----------------------------------------------------------------- config (env)
BASE_MODEL_PATH = Path(os.environ["BASE_MODEL_PATH"])
DATASET_PATH = Path(os.environ["DATASET_PATH"])
RUN_DIR = Path(os.environ["RUN_DIR"])
SCRATCH = Path(os.environ.get("SCRATCH", "/scratch"))
MAX_STEPS = int(os.environ.get("MAX_STEPS", "200"))
SAVE_STEPS = int(os.environ.get("SAVE_STEPS", "50"))
LEARNING_RATE = float(os.environ.get("LEARNING_RATE", "2e-4"))
MAX_LENGTH = int(os.environ.get("MAX_LENGTH", "1024"))
PER_DEVICE_BATCH = int(os.environ.get("PER_DEVICE_BATCH", "4"))
GRAD_ACCUM = int(os.environ.get("GRAD_ACCUM", "4"))
LORA_R = int(os.environ.get("LORA_R", "16"))
TRAIN_SAMPLES = int(os.environ.get("TRAIN_SAMPLES", "2000"))

CHECKPOINTS_DIR = RUN_DIR / "checkpoints"
MODEL_DIR = RUN_DIR / "model"
OUTPUT_DIR = SCRATCH / "trainer-output"  # Trainer's local checkpoints
MERGED_DIR = SCRATCH / "merged-model"  # merged model staged before the bucket copy
SEED = 42

STOP_REQUESTED = False


def on_sigterm(_signum, _frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    log("SIGTERM received: will checkpoint at the end of the current step and exit")


def log(msg: str) -> None:
    if os.environ.get("RANK", "0") == "0":
        print(f"[finetune] {msg}", flush=True)


def precision() -> str:
    """bf16 on Ampere+; fp16 AMP on T4 (g4dn has no bf16); fp32 on CPU."""
    if torch.cuda.is_available():
        return "bf16" if torch.cuda.is_bf16_supported() else "fp16"
    return "fp32"


PRECISION = precision()


class BucketCheckpointCallback(TrainerCallback):
    """Mirrors every local checkpoint into the bucket and reacts to SIGTERM."""

    def on_step_end(
        self,
        args: TrainingArguments,
        state: TrainerState,
        control: TrainerControl,
        **kwargs,
    ):
        if STOP_REQUESTED:
            # Trainer checks these right after on_step_end: save this step, then stop.
            control.should_save = True
            control.should_training_stop = True
        return control

    def on_save(
        self,
        args: TrainingArguments,
        state: TrainerState,
        control: TrainerControl,
        **kwargs,
    ):
        if not state.is_world_process_zero:
            return control
        name = f"checkpoint-{state.global_step}"
        local, remote = Path(args.output_dir) / name, CHECKPOINTS_DIR / name
        if is_complete(remote):
            return control
        try:
            copied = copy_tree_new_files(local, remote)
        except FileExistsError as err:
            # An earlier attempt left a partial checkpoint-N with different bytes,
            # and the bucket cannot overwrite it. Leave it unmarked (never a resume
            # point) and keep training; the next save goes to a new directory.
            log(f"WARNING: not uploading {name}: {err}")
            return control
        mark_complete(remote)
        log(f"checkpoint uploaded: {remote} ({copied} files)")
        return control


def restore_latest_checkpoint() -> Path | None:
    """Copy the newest complete bucket checkpoint to scratch; return its local path."""
    remote = latest_complete_checkpoint(RUN_DIR)
    if remote is None:
        log(f"no complete checkpoint under {CHECKPOINTS_DIR}, starting from scratch")
        return None
    local = OUTPUT_DIR / remote.name
    shutil.rmtree(local, ignore_errors=True)  # scratch is a normal disk; start clean
    copy_tree_new_files(remote, local)
    log(f"RESUMING from {remote}")
    return local


def load_train_dataset():
    files = str(DATASET_PATH / "data" / "train-*.parquet")
    ds = load_dataset("parquet", data_files={"train": files}, split="train")
    # Fixed-seed subset: every retry trains on exactly the same samples, so the data
    # position restored from a checkpoint still means the same thing.
    ds = ds.shuffle(seed=SEED).select(range(min(TRAIN_SAMPLES, len(ds))))
    # Conversational format: TRL applies the model's chat template itself.
    return ds.select_columns(["messages"])


def checkpoint_step(checkpoint: Path | None) -> int:
    return int(checkpoint.name.removeprefix("checkpoint-")) if checkpoint else 0


def train(resume_from: Path | None) -> Path:
    """Run (or resume) LoRA SFT; returns the local dir of the final checkpoint."""
    # fp16 AMP needs fp32 master weights (GradScaler cannot unscale fp16 grads), so the
    # T4 path loads fp32; bf16 loads directly in bf16 to halve memory.
    load_dtype = torch.bfloat16 if PRECISION == "bf16" else torch.float32
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_PATH)
    model = AutoModelForCausalLM.from_pretrained(BASE_MODEL_PATH, dtype=load_dtype)
    train_ds = load_train_dataset()
    log(f"train samples: {len(train_ds)}")
    config = SFTConfig(
        output_dir=str(OUTPUT_DIR),
        max_steps=MAX_STEPS,
        per_device_train_batch_size=PER_DEVICE_BATCH,
        gradient_accumulation_steps=GRAD_ACCUM,
        learning_rate=LEARNING_RATE,
        warmup_steps=max(1, MAX_STEPS // 20),
        max_length=MAX_LENGTH,
        bf16=PRECISION == "bf16",
        fp16=PRECISION == "fp16",
        gradient_checkpointing=True,  # compute for memory: 1024-token batches fit a T4
        save_strategy="steps",
        save_steps=SAVE_STEPS,
        save_total_limit=2,  # local scratch only; the bucket keeps every checkpoint
        logging_steps=max(1, min(10, MAX_STEPS // 10)),
        report_to="none",
        seed=SEED,
    )
    lora = LoraConfig(
        r=LORA_R,
        lora_alpha=2 * LORA_R,
        lora_dropout=0.05,
        target_modules="all-linear",
        task_type="CAUSAL_LM",
    )
    trainer = SFTTrainer(
        model=model,
        args=config,
        train_dataset=train_ds,
        processing_class=tokenizer,
        peft_config=lora,
        callbacks=[BucketCheckpointCallback()],
    )
    trainer.model.print_trainable_parameters()

    resume = str(resume_from) if resume_from else None
    result = trainer.train(resume_from_checkpoint=resume)
    step = trainer.state.global_step

    if STOP_REQUESTED:
        # Non-zero and not 1: the workflow retries every exit code except 1.
        log(f"stopped at step {step} after SIGTERM; exiting 143 so the step is retried")
        sys.exit(143)
    log(f"training complete: step={step} train_loss={result.training_loss:.4f}")
    # save_strategy="steps" always saves once more at max_steps, so this dir exists.
    return OUTPUT_DIR / f"checkpoint-{step}"


def save_merged_model(adapter_dir: Path) -> None:
    """Merge the LoRA adapter into the base weights, stage on scratch, upload."""
    # CPU + fp32: a 0.6B merge takes seconds, and the result does not depend on which
    # GPU type a retry lands on (see the module docstring).
    base = AutoModelForCausalLM.from_pretrained(BASE_MODEL_PATH, dtype=torch.float32)
    merged = PeftModel.from_pretrained(base, adapter_dir).merge_and_unload()
    # Save in the base model's own dtype so the artifact serves exactly like the base.
    base_dtype = AutoConfig.from_pretrained(BASE_MODEL_PATH).dtype or torch.float32
    merged = merged.to(dtype=base_dtype)
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_PATH)
    shutil.rmtree(MERGED_DIR, ignore_errors=True)
    merged.save_pretrained(MERGED_DIR)
    tokenizer.save_pretrained(MERGED_DIR)
    try:
        copied = copy_tree_new_files(MERGED_DIR, MODEL_DIR)
    except FileExistsError as err:
        sys.exit(
            f"{MODEL_DIR} holds files from an earlier, interrupted upload that "
            f"differ from this attempt ({err}). Delete {MODEL_DIR} and retry."
        )
    mark_complete(MODEL_DIR)
    log(f"merged model written to {MODEL_DIR} ({copied} files)")


def main() -> None:
    signal.signal(signal.SIGTERM, on_sigterm)

    if is_complete(MODEL_DIR):
        log(f"{MODEL_DIR} is already complete; nothing to do")
        return

    log(f"base={BASE_MODEL_PATH} precision={PRECISION} run_dir={RUN_DIR}")

    resume_from = restore_latest_checkpoint()
    if checkpoint_step(resume_from) >= MAX_STEPS:
        log(f"{resume_from.name} reached MAX_STEPS={MAX_STEPS}; merging, no training")
        final_checkpoint = resume_from
    else:
        final_checkpoint = train(resume_from)

    if os.environ.get("RANK", "0") == "0":
        save_merged_model(final_checkpoint)


if __name__ == "__main__":
    main()
