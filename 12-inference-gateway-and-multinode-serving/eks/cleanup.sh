#!/usr/bin/env bash
# Remove chapter workloads. Deleting the Gateway removes the Service NGF creates for the
# listener; if that Service is type LoadBalancer, confirm the ELB/NLB is actually gone in the
# AWS console (dangling ELBs bill hourly). The spot-gpu node group is shared with
# 01-gpu-nodes-and-scheduling and scales to 0 on its own.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
