#!/usr/bin/env bash
# Remove chapter workloads. The gpuspot pool is shared with 01-gpu-nodes-and-scheduling and
# autoscales to 0 on its own.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
