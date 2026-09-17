#!/usr/bin/env bash
# Remove chapter workloads, scale GPU groups to 0. UNINSTALL_PLUGIN=true removes the device plugin
# (do this before chapter 02 if you'll let the GPU Operator manage it).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
kubectl delete -k "$HERE" --ignore-not-found || true
for ng in spot-gpu ondemand-gpu; do
  eksctl scale nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --name "$ng" --nodes 0 --nodes-min 0 2>/dev/null || true
done
if [[ "${UNINSTALL_PLUGIN:-false}" == "true" ]]; then helm -n nvidia-device-plugin uninstall nvdp || true; fi
