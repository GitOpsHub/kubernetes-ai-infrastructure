# /// script
# requires-python = ">=3.12"
# dependencies = ["huggingface_hub==1.32.0"]
# ///
"""Chapter 19 - pull one pinned Hugging Face repo (model or dataset) into the bucket.

Runs as the first step of the `hf-finetune-pipeline` Argo WorkflowTemplate:
    uv run /opt/ch19/hf_pull.py
in the uv image, so the dependency pin above is the whole install - no custom image.

Env
  REPO_ID     e.g. Qwen/Qwen3-0.6B or trl-lib/Capybara            (required)
  REPO_TYPE   model | dataset                                       (required)
  REVISION    commit SHA - pin it, so a retry can never mix revisions (required)
  STORE_ROOT  bucket mount (default /mnt/store)
  SCRATCH     local emptyDir (default /scratch)
  HF_TOKEN    optional; only needed for gated/private repos

Result: $STORE_ROOT/hf/<REPO_TYPE>s/<REPO_ID>/<REVISION>/ + _COMPLETE.
The destination is printed on stdout (the only stdout line) and written to
/tmp/dest.txt, which the workflow exposes as an output parameter.

Why download to scratch and copy, instead of downloading straight into the mount?
Bucket CSI mounts (Mountpoint for S3, GCS FUSE) cannot rename, and cannot overwrite
without extra mount options. snapshot_download writes *.incomplete temp files and
renames them into place, so it must run on a real disk. We then copy each file as a
NEW object, sequentially, and write _COMPLETE LAST: readers only trust a directory
with the marker, so a pod killed mid-copy (spot reclaim) never publishes a half repo.
"""

import os
import shutil
import sys
from datetime import UTC, datetime
from pathlib import Path

from huggingface_hub import HfApi, snapshot_download

MARKER = "_COMPLETE"
DEST_PARAM_FILE = Path("/tmp/dest.txt")

# Never needed to train or serve: docs, git metadata, ONNX exports, TensorBoard logs.
ALWAYS_IGNORE = ["*.md", ".gitattributes", "onnx/*", "*.onnx", "runs/*"]
# Legacy weight formats. Skipped only when the repo also ships safetensors, so a
# repo that has nothing but pytorch_model.bin still downloads something loadable.
LEGACY_WEIGHTS = ["*.bin", "*.pt", "*.pth", "*.ckpt", "*.h5", "*.msgpack"]


def log(msg: str) -> None:
    # stdout is reserved for the destination path; progress goes to stderr.
    print(msg, file=sys.stderr, flush=True)


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"{name} is required")
    return value


def ignore_patterns(api: HfApi, repo_id: str, repo_type: str, rev: str) -> list[str]:
    patterns = list(ALWAYS_IGNORE)
    if repo_type == "model":
        files = api.list_repo_files(repo_id, repo_type=repo_type, revision=rev)
        if any(f.endswith(".safetensors") for f in files):
            patterns += LEGACY_WEIGHTS
    return patterns


def copy_new_files(src: Path, dst: Path) -> None:
    """Copy every regular file under src to dst, never overwriting.

    A file already at the destination is left alone when its size matches: it can
    only come from an earlier attempt at the same pinned commit (object-store FUSE
    mounts only make a file visible once it has been fully uploaded), so it is the
    same content. A size mismatch means something else wrote there - fail loudly
    rather than guess.
    """
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        # snapshot_download(local_dir=...) keeps its own bookkeeping in .cache/.
        if not path.is_file() or ".cache" in rel.parts:
            continue
        target = dst / rel
        if target.exists():
            if target.stat().st_size == path.stat().st_size:
                log(f"  exists, skipping  {rel}")
                continue
            raise FileExistsError(
                f"{target} exists with a different size and the bucket cannot "
                "overwrite it. Delete the incomplete destination directory and retry."
            )
        target.parent.mkdir(parents=True, exist_ok=True)
        # copyfile, not copy2: copy2 also copies mode/timestamps, and chmod/utime are
        # not supported on bucket mounts.
        shutil.copyfile(path, target)
        log(f"  copied  {rel} ({path.stat().st_size / 1e6:.1f} MB)")


def main() -> None:
    repo_id = required_env("REPO_ID")
    repo_type = required_env("REPO_TYPE")
    revision = required_env("REVISION")
    if repo_type not in ("model", "dataset"):
        sys.exit(f"REPO_TYPE must be 'model' or 'dataset', got {repo_type!r}")
    store_root = Path(os.environ.get("STORE_ROOT", "/mnt/store"))
    scratch = Path(os.environ.get("SCRATCH", "/scratch"))
    token = os.environ.get("HF_TOKEN") or None

    dest = store_root / "hf" / f"{repo_type}s" / repo_id / revision
    if (dest / MARKER).exists():
        log(f"{repo_type} {repo_id}@{revision} already in the store")
    else:
        local = scratch / "hf-pull" / f"{repo_type}s" / repo_id / revision
        api = HfApi(token=token)
        patterns = ignore_patterns(api, repo_id, repo_type, revision)
        log(f"downloading {repo_type} {repo_id}@{revision} -> {local}")
        log(f"  ignoring {patterns}")
        snapshot_download(
            repo_id,
            repo_type=repo_type,
            revision=revision,
            local_dir=local,
            ignore_patterns=patterns,
            token=token,
        )
        log(f"copying to {dest}")
        dest.mkdir(parents=True, exist_ok=True)
        copy_new_files(local, dest)
        (dest / MARKER).write_text(datetime.now(UTC).isoformat() + "\n")
        log(f"wrote {dest / MARKER}")

    DEST_PARAM_FILE.write_text(str(dest))
    print(dest, flush=True)


if __name__ == "__main__":
    main()
