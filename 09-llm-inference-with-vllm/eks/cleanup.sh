#!/usr/bin/env bash
# Remove chapter workloads. EKS does not autoscale to 0 by itself — if no other chapter needs the
# GPU nodegroup, scale it down: ../../01-gpu-nodes-and-scheduling/eks/scale-gpu-nodegroup.sh NODES=0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
