#!/usr/bin/env bash
# Remove chapter workloads. Confirm the Azure Load Balancer NGF's Gateway Service created is
# actually deleted (Azure Portal > Load balancers) -- dangling public LBs bill hourly.
# The gpuspot pool is shared with 01-gpu-nodes-and-scheduling and scales to 0 on its own.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
