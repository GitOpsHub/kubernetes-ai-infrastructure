#!/usr/bin/env bash
# Remove chapter workloads. The GPU node pool is shared with 01-gpu-nodes-and-scheduling and scales
# to 0 on its own (min-nodes 0) — delete it there with DELETE_POOL=true if you're done with GPUs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
