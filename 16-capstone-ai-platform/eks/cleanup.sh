#!/usr/bin/env bash
# Teardown in REVERSE dependency order. Every line is commented — uncomment and run a phase at a
# time. Node-group deletes are the expensive part; do those last so you can still `kubectl
# describe` anything that failed to drain cleanly. Each chapter's own README §7 (Cleanup) has the
# exact commands referenced below.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "== Reverse Phase 7-6: capstone + pipelines =="
# kubectl delete -k 16-capstone-ai-platform/eks --ignore-not-found
# ./15-mlops-gitops-and-pipelines/cpu-lab/cleanup.sh

echo "== Reverse Phase 5: security (14-multi-tenancy-and-security/README.md §7) =="

echo "== Reverse Phase 4: gateway/autoscaling/node-autoscaling =="
# kubectl delete -k 12-inference-gateway-and-multinode-serving/eks --ignore-not-found
# See 12-inference-gateway-and-multinode-serving/README.md §7
# kubectl delete -k 10-autoscaling-inference/eks --ignore-not-found
# See 13-node-autoscaling-and-cost/README.md §7

echo "== Reverse Phase 3: serving/training frameworks =="
# See 11-kserve/README.md §7
# kubectl delete -k 09-llm-inference-with-vllm/eks --ignore-not-found
# See 09-llm-inference-with-vllm/README.md §7, 07-distributed-training-kubeflow-trainer/README.md §7

echo "== Reverse Phase 2: Kueue (06-batch-jobs-and-kueue/README.md §7) =="

echo "== Reverse Phase 1: storage/observability (node groups) =="
# See 05-model-storage-and-data/README.md §7
# helm uninstall kube-prometheus-stack -n monitoring

echo "== Reverse Phase 0: GPU/CPU node groups + cluster (most expensive, delete last) =="
# See 02-nvidia-gpu-operator/README.md §7, 01-gpu-nodes-and-scheduling/README.md §7,
# 00-prerequisites-and-cluster-setup/README.md §7   # deletes the whole cluster

echo "Every command above is commented out on purpose — uncomment and run a phase at a time."
