# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#     "langchain-core==1.6.3",
#     "langchain-openai==1.6.2",
#     "langchain-text-splitters==1.1.2",
#     "huggingface-hub==1.32.0",
#     "numpy==2.5.3",
# ]
# ///
"""Offline batch inference: questions from a JSONL file -> answers in a JSONL file on the bucket.

Run by the `langchain-batch-inference` WorkflowTemplate as `uv run /opt/app/batch_infer.py`.

Input  ($INPUT_PATH, one JSON object per line):   {"id": "q01", "question": "..."}
Output ($OUTPUT_DIR/results.jsonl, one per input): {"id", "question", "answer", "sources", "error",
                                                    "model", "use_rag"}
then   ($OUTPUT_DIR/_COMPLETE, written LAST):      JSON summary incl. "results_file"

Storage rules (bucket mounts via Mountpoint for S3 / GCS FUSE, see chapter 05): write only NEW
files, sequentially, and never overwrite or rename. So:
  - `_COMPLETE` exists: an earlier attempt already finished, so exit 0 and do nothing (an Argo
    retry or a re-submitted step is idempotent).
  - `results.jsonl` exists but `_COMPLETE` doesn't: an earlier attempt died mid-write (possible
    on a plain PVC; bucket mounts usually drop an unclosed upload). We can't overwrite it, so
    write `results-<UTC timestamp>.jsonl` instead. `_COMPLETE` names the file that counts.
  - More than 50% of questions failed: write NOTHING and exit 1. Writing `_COMPLETE` would
    make the retry skip itself and hide the failure. Writing a partial results file would just
    leave junk behind. Per-item errors go to the log instead.
  - At most 50% failed: write the results with per-row "error" fields, then `_COMPLETE`, exit 0.

LLM calls run concurrently through `chain.batch(..., max_concurrency=CONCURRENCY)`. vLLM's
continuous batching turns concurrent requests into GPU batches, so CONCURRENCY is the throughput
knob. Setting it higher than vLLM's --max-num-seqs only adds queueing.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

import rag_chain  # sibling module in the same dir (uv run puts the script dir on sys.path)

log = logging.getLogger("batch_infer")

MAX_FAILURE_RATIO = 0.5


def read_inputs(path: Path) -> list[dict]:
    rows = []
    for lineno, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line.strip():
            continue
        row = json.loads(line)
        if not isinstance(row.get("question"), str) or not row["question"].strip():
            raise ValueError(f"{path}:{lineno}: missing or empty 'question'")
        rows.append({"id": str(row.get("id", lineno)), "question": row["question"]})
    if not rows:
        raise ValueError(f"{path} contains no questions")
    return rows


def pick_results_path(output_dir: Path) -> Path:
    default = output_dir / "results.jsonl"
    if not default.exists():
        return default
    alt = output_dir / f"results-{datetime.now(UTC):%Y%m%dT%H%M%SZ}.jsonl"
    log.warning(
        "%s exists without _COMPLETE (an earlier attempt died mid-write); it can't be "
        "overwritten on a bucket mount, so writing %s instead",
        default,
        alt.name,
    )
    return alt


def write_new_file(path: Path, text: str) -> None:
    # "x" = create-only: fails instead of silently overwriting, the same contract the bucket
    # mount enforces, so a plain-PVC run (cpu-lab) behaves the same way.
    with path.open("x", encoding="utf-8") as f:
        f.write(text)


def main() -> int:
    rag_chain.configure_logging()
    settings = rag_chain.Settings.from_env()
    use_rag = rag_chain.env_bool("USE_RAG", "true")
    concurrency = int(os.environ.get("CONCURRENCY", "8"))
    input_path = Path(
        os.environ.get("INPUT_PATH", "/mnt/store/batch/inputs/prompts.jsonl")
    )
    if not os.environ.get("OUTPUT_DIR"):
        log.error(
            "OUTPUT_DIR is required (the workflow sets /mnt/store/batch/<workflow name>)"
        )
        return 2
    output_dir = Path(os.environ["OUTPUT_DIR"])

    complete = output_dir / "_COMPLETE"
    if complete.exists():
        log.info("%s exists: this batch already finished, nothing to do", complete)
        return 0

    inputs = read_inputs(input_path)
    log.info(
        "batch: %d questions from %s, use_rag=%s, concurrency=%d, llm=%s model=%s",
        len(inputs),
        input_path,
        use_rag,
        concurrency,
        settings.openai_base_url,
        settings.chat_model,
    )

    llm = rag_chain.build_llm(settings)
    if use_rag:
        store = rag_chain.build_vector_store(settings)
        chain = rag_chain.build_rag_chain(
            store.as_retriever(search_kwargs={"k": settings.top_k}), llm
        )
    else:
        chain = rag_chain.build_chat_chain(llm)

    started = time.monotonic()
    # return_exceptions=True: one bad item (timeout, 400 for an over-long prompt) becomes an
    # Exception in its slot instead of aborting the other N-1 answers.
    outputs = chain.batch(
        [{"question": r["question"]} for r in inputs],
        config={"max_concurrency": concurrency},
        return_exceptions=True,
    )
    elapsed = time.monotonic() - started

    results, failed = [], 0
    for row, out in zip(inputs, outputs, strict=True):
        result = {**row, "answer": None, "sources": [], "error": None}
        if isinstance(out, Exception):
            failed += 1
            result["error"] = f"{type(out).__name__}: {out}"
            log.warning("id=%s failed: %s", row["id"], result["error"][:300])
        elif use_rag:
            result["answer"] = out["answer"]
            result["sources"] = rag_chain.sources_of(out["docs"])
        else:
            result["answer"] = out
        result["model"] = settings.chat_model
        result["use_rag"] = use_rag
        results.append(result)

    total = len(inputs)
    log.info(
        "batch done in %.1fs: %d ok, %d failed (%.1f q/s)",
        elapsed,
        total - failed,
        failed,
        total / elapsed if elapsed else 0.0,
    )
    if failed / total > MAX_FAILURE_RATIO:
        log.error(
            "%d/%d (>%.0f%%) failed -- writing nothing to %s so a retry starts clean",
            failed,
            total,
            MAX_FAILURE_RATIO * 100,
            output_dir,
        )
        return 1

    output_dir.mkdir(parents=True, exist_ok=True)
    results_path = pick_results_path(output_dir)
    write_new_file(
        results_path, "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results)
    )
    summary = {
        "results_file": results_path.name,
        "total": total,
        "failed": failed,
        "use_rag": use_rag,
        "model": settings.chat_model,
        "elapsed_seconds": round(elapsed, 2),
        "finished_at": datetime.now(UTC).isoformat(timespec="seconds"),
    }
    # LAST: its presence is what marks the results as valid.
    write_new_file(complete, json.dumps(summary) + "\n")
    log.info("wrote %s and %s", results_path, complete)
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
