"""Chapter 19 - write-once helpers for the bucket-backed model store.

/mnt/store is a bucket mounted through a CSI FUSE driver (Mountpoint for S3, GCS FUSE,
Azure Blob CSI). Those mounts only reliably support creating NEW files written
sequentially: no rename, no overwrite, no chmod. Everything that lands in the store
therefore follows one pattern:

  1. build the artifact on local scratch disk (emptyDir),
  2. copy it file by file into a fresh directory in the store,
  3. write a `_COMPLETE` marker LAST.

Readers only trust directories that carry the marker, so a pod killed halfway
through step 2 (spot reclaim) leaves an ignorable partial directory, never a corrupt
"ready" artifact.
"""

import filecmp
import re
import shutil
from datetime import UTC, datetime
from pathlib import Path

MARKER = "_COMPLETE"
_CHECKPOINT_RE = re.compile(r"^checkpoint-(\d+)$")


def is_complete(directory: str | Path) -> bool:
    return (Path(directory) / MARKER).is_file()


def mark_complete(directory: str | Path) -> None:
    """Write the marker. Call only after every other file has been copied."""
    marker = Path(directory) / MARKER
    if marker.exists():  # never overwrite, even the marker
        return
    marker.write_text(datetime.now(UTC).isoformat() + "\n")


def copy_tree_new_files(src: str | Path, dst: str | Path) -> int:
    """Copy every regular file under src into dst, creating new files only.

    Skipped: `.cache/` bookkeeping dirs and the `_COMPLETE` marker itself (the
    destination gets its own marker from mark_complete once the copy has finished).

    A destination file that already exists is never overwritten. If it is
    byte-identical (left by an earlier attempt that died before writing the marker)
    it is skipped; otherwise FileExistsError is raised, because the bucket cannot
    replace it and mixing two attempts' files would be silently wrong.

    Returns the number of files actually copied.
    """
    src, dst = Path(src), Path(dst)
    copied = 0
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        if not path.is_file() or path.name == MARKER or ".cache" in rel.parts:
            continue
        target = dst / rel
        if target.exists():
            if filecmp.cmp(path, target, shallow=False):
                continue
            raise FileExistsError(f"{target} already exists with different content")
        target.parent.mkdir(parents=True, exist_ok=True)
        # copyfile, not copy2: copy2 also sets mode/mtime, which bucket mounts reject.
        shutil.copyfile(path, target)
        copied += 1
    return copied


def latest_complete_checkpoint(run_dir: str | Path) -> Path | None:
    """Newest `<run_dir>/checkpoints/checkpoint-<N>` that has a `_COMPLETE` marker."""
    root = Path(run_dir) / "checkpoints"
    if not root.is_dir():
        return None
    complete = [
        (int(m.group(1)), path)
        for path in root.iterdir()
        if (m := _CHECKPOINT_RE.match(path.name)) and is_complete(path)
    ]
    return max(complete)[1] if complete else None
