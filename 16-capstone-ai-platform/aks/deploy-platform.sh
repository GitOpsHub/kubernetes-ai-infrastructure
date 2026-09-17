#!/usr/bin/env bash
# The capstone runbook: every command below is one you already ran (or could have) in
# chapters 00-15, in the order that makes each dependency available before the next chapter
# needs it. This script does not run anything by itself when you source/review it — read it,
# then run it a phase at a time, checking `kubectl get pods -A` between phases. It assumes
# ${AKS_CLUSTER} already exists (chapter 00) with GPU quota approved.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/env.sh"
source "$ROOT/versions.env"
cd "$ROOT"

echo "== Phase 0: cluster + spot CPU/GPU node pools (ch00-02) =="
# ./00-prerequisites-and-cluster-setup/aks/create-cluster.sh
# ./01-gpu-nodes-and-scheduling/aks/create-gpu-nodepool.sh
# ./02-nvidia-gpu-operator/aks/install.sh

echo "== Phase 1: observability + storage (ch04-05) =="
# ./04-gpu-observability/aks/install-kube-prometheus-stack.sh
# ./05-model-storage-and-data/aks/setup-blob-iam.sh
# kubectl apply -k 05-model-storage-and-data/aks

echo "== Phase 2: quotas + scheduling (ch06) =="
# kubectl apply -k 06-batch-jobs-and-kueue/cpu-lab   # namespace+flavors+cohort+queues (cloud-agnostic bases)
# ./06-batch-jobs-and-kueue/aks/create-nodepool.sh
# ./06-batch-jobs-and-kueue/aks/install-kueue.sh
# kubectl apply -k 06-batch-jobs-and-kueue/aks

echo "== Phase 3: training + serving frameworks (ch07-09, ch11) =="
# ./07-distributed-training-kubeflow-trainer/aks/create-gpu-nodepool.sh
# ./07-distributed-training-kubeflow-trainer/aks/setup-storage.sh
# ./07-distributed-training-kubeflow-trainer/aks/install.sh
# kubectl apply -k 07-distributed-training-kubeflow-trainer/aks
# kubectl apply -k 07-distributed-training-kubeflow-trainer/kueue/aks
# HF_TOKEN="$HF_TOKEN" ./09-llm-inference-with-vllm/common/create-hf-secret.sh ch09-vllm
# kubectl apply -k 09-llm-inference-with-vllm/aks
# ./11-kserve/aks/install-kserve.sh   # optional: KServe path instead of/alongside raw vLLM

echo "== Phase 4: gateway, multi-node serving, autoscaling, node autoscaling (ch10, 12-13) =="
# ./12-inference-gateway-and-multinode-serving/common/install-gateway-crds.sh
# ./12-inference-gateway-and-multinode-serving/common/install-lws.sh
# ./12-inference-gateway-and-multinode-serving/aks/install-nginx-gateway-fabric.sh
# kubectl apply -k 12-inference-gateway-and-multinode-serving/aks
# ./10-autoscaling-inference/aks/install-keda.sh
# ./10-autoscaling-inference/aks/install-prometheus-adapter.sh
# kubectl apply -k 10-autoscaling-inference/aks
# ./13-node-autoscaling-and-cost/aks/enable-nap.sh
# kubectl apply -k 13-node-autoscaling-and-cost/aks

echo "== Phase 5: multi-tenancy + secrets + supply chain (ch14) =="
# ./14-multi-tenancy-and-security/aks/install-external-secrets.sh
# ./14-multi-tenancy-and-security/aks/install-kyverno.sh
# kubectl apply -k 14-multi-tenancy-and-security/aks

echo "== Phase 6: GitOps + pipelines + registry (ch15) =="
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-argo-workflows.sh   # or via Argo CD, see ch15 README
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-mlflow.sh
# kubectl apply -k 15-mlops-gitops-and-pipelines/cpu-lab

echo "== Phase 7: capstone glue (ch16 — this chapter) =="
# kubectl apply -k 16-capstone-ai-platform/aks
# argo submit --watch -n ch15-pipelines --from workflowtemplate/platform-e2e

echo "Every command above is commented out on purpose — uncomment and run one phase at a time."
