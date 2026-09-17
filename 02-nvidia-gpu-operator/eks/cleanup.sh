#!/usr/bin/env bash
# Uninstall the GPU Operator release. Does not touch the EKS GPU nodegroup (see
# 01-gpu-nodes-and-scheduling/eks/scale-gpu-nodegroup.sh NODES=0 or cleanup.sh for that).
set -euo pipefail
helm -n gpu-operator uninstall gpu-operator || true
kubectl delete clusterpolicy cluster-policy --ignore-not-found
echo "CRDs are left in place by 'helm uninstall'; delete manually only if you're done with the chart:"
echo "  kubectl get crd -o name | grep nvidia.com"
