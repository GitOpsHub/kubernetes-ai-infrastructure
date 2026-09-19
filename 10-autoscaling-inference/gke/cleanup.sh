#!/usr/bin/env bash
# Remove this chapter's autoscaling objects and the prometheus-adapter / KEDA releases (README section 7).
# Leaves chapter 09's vLLM Deployment and chapter 04's kube-prometheus-stack in place — they belong to
# those chapters. Safe to re-run: every delete tolerates "not found".
# The GPU node pool is shared with 01-gpu-nodes-and-scheduling / 09 and scales to 0 on its own
# (min-nodes 0) once the vLLM replicas autoscaling brought up are gone.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$HERE/../common"

# ScaledObject/HPA first, while KEDA is still running: KEDA puts a finalizer on each ScaledObject,
# and uninstalling the operator before deleting them leaves the object stuck in Terminating.
kubectl delete -k "$COMMON/keda" --ignore-not-found || true
kubectl delete -k "$COMMON/hpa" --ignore-not-found || true
kubectl delete -k "$COMMON/load-generator" --ignore-not-found || true
kubectl delete -k "$HERE" --ignore-not-found || true   # ServiceMonitor

# Uninstall the Helm releases only if they're present (another chapter may already have removed them).
if helm status prometheus-adapter -n monitoring > /dev/null 2>&1; then
  helm uninstall prometheus-adapter -n monitoring
fi
if helm status keda -n keda > /dev/null 2>&1; then
  helm uninstall keda -n keda
fi
kubectl delete namespace keda --ignore-not-found || true

echo "Done. vLLM (ch09-vllm) is untouched; if KEDA had scaled it to 0, scale it back with:"
echo "  kubectl -n ch09-vllm scale deploy vllm --replicas=1"
