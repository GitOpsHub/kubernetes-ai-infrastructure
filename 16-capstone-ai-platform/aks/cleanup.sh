#!/usr/bin/env bash
# Teardown in REVERSE dependency order. Like deploy-platform.sh, every line is commented —
# uncomment and run a phase at a time. Node-pool deletes are the expensive part; do those last
# so you can still `kubectl describe` anything that failed to drain cleanly.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "== Reverse Phase 7-6: capstone + pipelines =="
# kubectl delete -k 16-capstone-ai-platform/aks --ignore-not-found
# ./15-mlops-gitops-and-pipelines/cpu-lab/cleanup.sh

echo "== Reverse Phase 5: security =="
# ./14-multi-tenancy-and-security/aks/cleanup.sh

echo "== Reverse Phase 4: gateway/autoscaling/node-autoscaling =="
# kubectl delete -k 12-inference-gateway-and-multinode-serving/aks --ignore-not-found
# ./12-inference-gateway-and-multinode-serving/aks/cleanup.sh
# kubectl delete -k 10-autoscaling-inference/aks --ignore-not-found
# ./13-node-autoscaling-and-cost/aks/cleanup.sh

echo "== Reverse Phase 3: serving/training frameworks =="
# ./11-kserve/aks/cleanup.sh
# kubectl delete -k 09-llm-inference-with-vllm/aks --ignore-not-found
# ./09-llm-inference-with-vllm/aks/cleanup.sh
# ./07-distributed-training-kubeflow-trainer/aks/cleanup.sh

echo "== Reverse Phase 2: Kueue =="
# ./06-batch-jobs-and-kueue/aks/cleanup.sh

echo "== Reverse Phase 1: storage/observability (node pools) =="
# ./05-model-storage-and-data/aks/cleanup.sh
# helm uninstall kube-prometheus-stack -n monitoring

echo "== Reverse Phase 0: GPU/CPU node pools + cluster (most expensive, delete last) =="
# ./02-nvidia-gpu-operator/aks/cleanup.sh
# ./01-gpu-nodes-and-scheduling/aks/cleanup.sh
# ./00-prerequisites-and-cluster-setup/aks/cleanup.sh   # deletes the whole cluster

echo "Every command above is commented out on purpose — uncomment and run a phase at a time."
