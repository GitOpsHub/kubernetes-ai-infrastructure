#!/usr/bin/env bash
# Remove chapter workloads (this also deletes the Gateway, which tears down the GCP L7 load
# balancer it provisioned -- avoids leaving a forwarding rule/backend service billing you).
# The spot-gpu node pool is shared with 01-gpu-nodes-and-scheduling; it scales to 0 on its own.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
