#!/usr/bin/env bash
# Teardown in REVERSE dependency order. Like deploy-platform.sh, every line is commented —
# uncomment and run a phase at a time. Node-pool deletes are the expensive part; do those last
# so you can still `kubectl describe` anything that failed to drain cleanly.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "== Reverse Phase 7-6: capstone + pipelines =="
# kubectl delete -k 16-capstone-ai-platform/gke --ignore-not-found
# ./15-mlops-gitops-and-pipelines/cpu-lab/cleanup.sh

echo "== Reverse Phase 5: security =="
# ./14-multi-tenancy-and-security/gke/cleanup.sh

echo "== Reverse Phase 4: gateway/autoscaling/node-autoscaling =="
# kubectl delete -k 12-inference-gateway-and-multinode-serving/gke --ignore-not-found
# ./12-inference-gateway-and-multinode-serving/gke/cleanup.sh
# kubectl delete -k 10-autoscaling-inference/gke --ignore-not-found
# ./13-node-autoscaling-and-cost/gke/cleanup.sh

echo "== Reverse Phase 3: serving/training frameworks =="
# ./11-kserve/gke/cleanup.sh
# kubectl delete -k 09-llm-inference-with-vllm/gke --ignore-not-found
# ./09-llm-inference-with-vllm/gke/cleanup.sh
# ./07-distributed-training-kubeflow-trainer/gke/cleanup.sh

echo "== Reverse Phase 2: Kueue =="
# ./06-batch-jobs-and-kueue/gke/cleanup.sh

echo "== Reverse Phase 1: storage/observability (node pools) =="
# ./05-model-storage-and-data/gke/cleanup.sh
# helm uninstall kube-prometheus-stack -n monitoring

echo "== Reverse Phase 0: GPU/CPU node pools + cluster (most expensive, delete last) =="
# ./02-nvidia-gpu-operator/gke/cleanup.sh
# ./01-gpu-nodes-and-scheduling/gke/cleanup.sh
# ./00-prerequisites-and-cluster-setup/gke/cleanup.sh   # deletes the whole cluster

echo "Every command above is commented out on purpose — uncomment and run a phase at a time."
