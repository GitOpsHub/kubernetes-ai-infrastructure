#!/usr/bin/env bash
# Uninstall the GPU Operator release. Does not delete the GPU node pool (see 01-gpu-nodes-and-scheduling
# /gke/cleanup.sh or scale-gpu-pool.sh NODES=0 for that).
set -euo pipefail
helm -n gpu-operator uninstall gpu-operator || true
kubectl delete clusterpolicy cluster-policy --ignore-not-found
echo "Note: CRDs installed by the chart (clusterpolicies.nvidia.com, nvdrivers.nvidia.com, ...) are"
echo "left in place by 'helm uninstall' on purpose; delete manually only if you're done with the chart:"
echo "  kubectl get crd -o name | grep nvidia.com"
