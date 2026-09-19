# Model storage: getting weights to the pod

An LLM server needs a large image **plus** model weights (1 GB to over 1 TB) on every pod start.
Pods start on every scale-up, every rollout and every spot reclaim. Treat model delivery like
artifact distribution: immutable, versioned, least-privilege, cached close to the nodes.

## Bucket-backed volumes

Each cloud mounts object storage as a volume through a CSI driver with keyless identity:

| Cloud | Driver | Identity |
|---|---|---|
| GKE | Cloud Storage FUSE CSI | Workload Identity Federation for GKE |
| EKS | Mountpoint for Amazon S3 CSI | EKS Pod Identity (`authenticationSource: pod`) |
| AKS | Azure Blob CSI (blobfuse2) | Azure Workload Identity |

## Write rules for bucket mounts

Mountpoint for S3 writes **new files only**. By default it can't overwrite, delete or rename, and
GCS FUSE renames on flat buckets are a non-atomic copy plus delete. So on this platform:

- Download or train into local scratch (an `emptyDir`) first, then copy the files onto the
  mount sequentially as new files. Tools like `hf download` write temp files and rename them,
  which fails on Mountpoint.
- Store models under an immutable path that includes the pinned revision, for example
  `hf/models/Qwen/Qwen3-0.6B/<commit-sha>/`. Pin revisions to commit SHAs, not `main`.
- Write a `_COMPLETE` marker file **last**. Readers treat a directory without it as invalid, so
  a copy interrupted by a spot reclaim is never served.
- An `Operation not permitted` error when copying onto an existing file means you're
  overwriting on Mountpoint. Use a new path instead.

## Separate writer and reader identities

Only loader jobs and pipelines get write access to the bucket. Serving pods such as vLLM use a
read-only identity and mount the volume `readOnly`. With `authenticationSource: pod`, the
Mountpoint process uses the workload pod's own ServiceAccount, so two pods sharing one PV can
still get different S3 permissions.
