#!/usr/bin/env bash
# The capstone runbook: every command below is one you already ran (or could have) in
# chapters 00-15, in the order that makes each dependency available before the next chapter
# needs it. This script does not run anything by itself when you source/review it — read it,
# then run it a phase at a time, checking `kubectl get pods -A` between phases. It assumes
# ${GKE_CLUSTER} already exists (chapter 00) with GPU quota approved.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/env.sh"
source "$ROOT/versions.env"
cd "$ROOT"

echo "== Phase 0: cluster + spot CPU/GPU node pools (ch00-02) =="
# ./00-prerequisites-and-cluster-setup/gke/create-cluster.sh
# ./01-gpu-nodes-and-scheduling/gke/create-gpu-nodepool.sh
# ./02-nvidia-gpu-operator/gke/install.sh

echo "== Phase 1: observability + storage (ch04-05) =="
# ./04-gpu-observability/gke/install-kube-prometheus-stack.sh
# ./05-model-storage-and-data/gke/setup-gcs-iam.sh
# kubectl apply -k 05-model-storage-and-data/gke

echo "== Phase 2: quotas + scheduling (ch06) =="
# kubectl apply -k 06-batch-jobs-and-kueue/cpu-lab   # namespace+flavors+cohort+queues (cloud-agnostic bases)
# ./06-batch-jobs-and-kueue/gke/create-nodepool.sh
# ./06-batch-jobs-and-kueue/gke/install-kueue.sh
# kubectl apply -k 06-batch-jobs-and-kueue/gke

echo "== Phase 3: training + serving frameworks (ch07-09, ch11) =="
# ./07-distributed-training-kubeflow-trainer/gke/create-gpu-nodepool.sh
# ./07-distributed-training-kubeflow-trainer/gke/setup-storage.sh
# ./07-distributed-training-kubeflow-trainer/gke/install.sh
# kubectl apply -k 07-distributed-training-kubeflow-trainer/gke
# kubectl apply -k 07-distributed-training-kubeflow-trainer/kueue/gke
# HF_TOKEN="$HF_TOKEN" ./09-llm-inference-with-vllm/common/create-hf-secret.sh ch09-vllm
# kubectl apply -k 09-llm-inference-with-vllm/gke
# ./11-kserve/gke/install-kserve.sh   # optional: KServe path instead of/alongside raw vLLM

echo "== Phase 4: gateway, multi-node serving, autoscaling, node autoscaling (ch10, 12-13) =="
# ./12-inference-gateway-and-multinode-serving/common/install-gateway-crds.sh
# ./12-inference-gateway-and-multinode-serving/common/install-lws.sh
# ./12-inference-gateway-and-multinode-serving/gke/create-gateway.sh
# kubectl apply -k 12-inference-gateway-and-multinode-serving/gke
# ./10-autoscaling-inference/gke/install-keda.sh
# ./10-autoscaling-inference/gke/install-prometheus-adapter.sh
# kubectl apply -k 10-autoscaling-inference/gke
# ./13-node-autoscaling-and-cost/gke/enable-nap.sh
# kubectl apply -k 13-node-autoscaling-and-cost/gke

echo "== Phase 5: multi-tenancy + secrets + supply chain (ch14) =="
# ./14-multi-tenancy-and-security/gke/install-external-secrets.sh
# ./14-multi-tenancy-and-security/gke/install-kyverno.sh
# kubectl apply -k 14-multi-tenancy-and-security/gke

echo "== Phase 6: GitOps + pipelines + registry (ch15) =="
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-argo-workflows.sh   # or via Argo CD, see ch15 README
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-mlflow.sh
# kubectl apply -k 15-mlops-gitops-and-pipelines/cpu-lab

echo "== Phase 7: capstone glue (ch16 — this chapter) =="
# kubectl apply -k 16-capstone-ai-platform/gke
# argo submit --watch -n ch15-pipelines --from workflowtemplate/platform-e2e

echo "Every command above is commented out on purpose — uncomment and run one phase at a time."
