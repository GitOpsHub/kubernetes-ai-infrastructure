"""Chapter 19 - held-out loss / perplexity of the fine-tuned model, plus a quality gate.

Runs as the `evaluate` step of the `hf-finetune-pipeline` Argo WorkflowTemplate:
    python /app/evaluate.py

Env
  MODEL_PATH     merged model dir ($RUN_DIR/model, must carry _COMPLETE)   (required)
  DATASET_PATH   dataset dir from hf_pull.py; reads data/test-*.parquet    (required)
  RUN_DIR        /mnt/store/runs/<RUN_ID>                                  (required)
  EVAL_SAMPLES   test conversations to score (default 200)
  MAX_EVAL_LOSS  quality gate (default 2.5)
  MAX_LENGTH     truncate each conversation, same as training (default 1024)

Loss is the token-weighted mean next-token cross-entropy over whole chat-formatted
conversations - the same objective SFT optimised (finetune.py keeps TRL's default
assistant_only_loss=False, so system/user tokens count in both) - and perplexity = exp(loss).

Results go to $RUN_DIR/eval/metrics.json, written once as a new file (the bucket
cannot overwrite). If it already exists, a retried step re-reads it instead of
re-scoring, so the gate always judges the recorded numbers. The loss is also written
to /tmp/eval_loss.txt for the workflow's output parameter.

Exit 1 when eval_loss > MAX_EVAL_LOSS. The workflow treats exit 1 as final (no
retry), which stops the DAG before the publish step.
"""

import json
import math
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import torch
from datasets import load_dataset
from transformers import AutoModelForCausalLM, AutoTokenizer

from store import is_complete

MODEL_PATH = Path(os.environ["MODEL_PATH"])
DATASET_PATH = Path(os.environ["DATASET_PATH"])
RUN_DIR = Path(os.environ["RUN_DIR"])
EVAL_SAMPLES = int(os.environ.get("EVAL_SAMPLES", "200"))
MAX_EVAL_LOSS = float(os.environ.get("MAX_EVAL_LOSS", "2.5"))
MAX_LENGTH = int(os.environ.get("MAX_LENGTH", "1024"))

METRICS_FILE = RUN_DIR / "eval" / "metrics.json"
LOSS_PARAM_FILE = Path("/tmp/eval_loss.txt")
SEED = 42


def log(msg: str) -> None:
    print(f"[evaluate] {msg}", file=sys.stderr, flush=True)


def device_and_dtype() -> tuple[str, torch.dtype]:
    """bf16 on Ampere+, fp32 on T4 and CPU.

    Not fp16 on T4: Qwen-family activations can overflow fp16 and turn the loss into
    inf/NaN, and a 0.6B model in fp32 fits a 16 GB T4 easily. including_emulation=False
    because the default also reports bf16 "supported" (emulated, slow) on a T4.
    """
    if torch.cuda.is_available():
        bf16 = torch.cuda.is_bf16_supported(including_emulation=False)
        return "cuda", torch.bfloat16 if bf16 else torch.float32
    return "cpu", torch.float32


@torch.inference_mode()
def score() -> dict:
    device, dtype = device_and_dtype()
    log(f"model={MODEL_PATH} device={device} dtype={dtype}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
    model = AutoModelForCausalLM.from_pretrained(MODEL_PATH, dtype=dtype)
    model = model.to(device).eval()

    files = str(DATASET_PATH / "data" / "test-*.parquet")
    ds = load_dataset("parquet", data_files={"test": files}, split="test")
    ds = ds.shuffle(seed=SEED).select(range(min(EVAL_SAMPLES, len(ds))))

    total_nll, total_tokens = 0.0, 0
    # One conversation per forward pass: no padding to mask out, and a 0.6B model
    # scores a few hundred conversations in seconds on a GPU.
    for example in ds:
        text = tokenizer.apply_chat_template(example["messages"], tokenize=False)
        ids = tokenizer(
            text,
            add_special_tokens=False,  # the chat template already added them
            truncation=True,
            max_length=MAX_LENGTH,
            return_tensors="pt",
        ).input_ids.to(device)
        predicted = ids.shape[1] - 1  # the first token has nothing to predict it from
        if predicted < 1:
            continue
        # labels=input_ids: the model shifts internally and returns the mean NLL over
        # the predicted tokens; re-weight by token count for a corpus-level mean.
        loss = model(input_ids=ids, labels=ids).loss.float().item()
        total_nll += loss * predicted
        total_tokens += predicted

    eval_loss = total_nll / total_tokens
    return {
        "eval_loss": round(eval_loss, 6),
        # min(): math.exp raises OverflowError above ~709; the gate catches such a loss anyway.
        "perplexity": round(math.exp(min(eval_loss, 700.0)), 4),
        "eval_samples": len(ds),
        "eval_tokens": total_tokens,
        "max_length": MAX_LENGTH,
        "model_path": str(MODEL_PATH),
        "dataset_path": str(DATASET_PATH),
        "evaluated_at": datetime.now(UTC).isoformat(),
    }


def main() -> None:
    if not is_complete(MODEL_PATH):
        sys.exit(f"{MODEL_PATH} has no _COMPLETE marker; finetune did not finish")

    if METRICS_FILE.exists():
        log(f"{METRICS_FILE} already exists (retried step); reusing it")
        metrics = json.loads(METRICS_FILE.read_text())
    else:
        metrics = score()
        METRICS_FILE.parent.mkdir(parents=True, exist_ok=True)
        # "x" = create-only: fails instead of overwriting if something raced us here.
        with METRICS_FILE.open("x") as f:
            json.dump(metrics, f, indent=2)
        log(f"wrote {METRICS_FILE}")

    print(json.dumps(metrics, indent=2), flush=True)
    LOSS_PARAM_FILE.write_text(f"{metrics['eval_loss']}")

    loss = metrics["eval_loss"]
    # NaN > x is False, so a NaN loss (numerical blow-up) would otherwise PASS the gate.
    if not math.isfinite(loss) or loss > MAX_EVAL_LOSS:
        log(f"GATE FAILED: eval_loss {loss} > MAX_EVAL_LOSS {MAX_EVAL_LOSS}")
        sys.exit(1)
    log(f"gate passed: eval_loss {loss} <= MAX_EVAL_LOSS {MAX_EVAL_LOSS}")


if __name__ == "__main__":
    main()
