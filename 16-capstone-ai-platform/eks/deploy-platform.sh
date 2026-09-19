#!/usr/bin/env bash
# The capstone runbook: every phase below is documented, as copy-pasteable commands, in that
# chapter's own README §4 (Lab) — this file is a sequencing reference, not a script to run as-is.
# It assumes ${EKS_CLUSTER} already exists (chapter 00) with GPU quota approved.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/env.sh"
source "$ROOT/versions.env"
cd "$ROOT"

echo "== Phase 0: cluster + spot CPU/GPU node group (ch00-02) =="
# See 00-prerequisites-and-cluster-setup/README.md §4, 01-gpu-nodes-and-scheduling/README.md §4,
# 02-nvidia-gpu-operator/README.md §4.

echo "== Phase 1: observability + storage (ch04-05) =="
# See 04-gpu-observability/README.md §4, 05-model-storage-and-data/README.md §4.

echo "== Phase 2: quotas + scheduling (ch06) =="
# kubectl apply -k 06-batch-jobs-and-kueue/cpu-lab   # namespace+flavors+cohort+queues (cloud-agnostic bases)
# See 06-batch-jobs-and-kueue/README.md §4 for the node group + Kueue install, then:
# kubectl apply -k 06-batch-jobs-and-kueue/eks

echo "== Phase 3: training + serving frameworks (ch07-09, ch11) =="
# See 07-distributed-training-kubeflow-trainer/README.md §4, then:
# kubectl apply -k 07-distributed-training-kubeflow-trainer/eks
# kubectl apply -k 07-distributed-training-kubeflow-trainer/kueue/eks
# HF_TOKEN="$HF_TOKEN" ./09-llm-inference-with-vllm/common/create-hf-secret.sh ch09-vllm
# kubectl apply -k 09-llm-inference-with-vllm/eks
# See 11-kserve/README.md §4   # optional: KServe path instead of/alongside raw vLLM

echo "== Phase 4: gateway, multi-node serving, autoscaling, node autoscaling (ch10, 12-13) =="
# See 12-inference-gateway-and-multinode-serving/README.md §4, then:
# kubectl apply -k 12-inference-gateway-and-multinode-serving/eks
# See 10-autoscaling-inference/README.md §4, then:
# kubectl apply -k 10-autoscaling-inference/eks
# See 13-node-autoscaling-and-cost/README.md §4, then:
# kubectl apply -k 13-node-autoscaling-and-cost/eks

echo "== Phase 5: multi-tenancy + secrets + supply chain (ch14) =="
# See 14-multi-tenancy-and-security/README.md §4, then:
# kubectl apply -k 14-multi-tenancy-and-security/eks

echo "== Phase 6: GitOps + pipelines + registry (ch15) =="
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-argo-workflows.sh   # or via Argo CD, see ch15 README
# ./15-mlops-gitops-and-pipelines/cpu-lab/install-mlflow.sh
# kubectl apply -k 15-mlops-gitops-and-pipelines/cpu-lab

echo "== Phase 7: capstone glue (ch16 — this chapter) =="
# kubectl apply -f 16-capstone-ai-platform/eks/clusterqueue-team-research.yaml
# kubectl apply -f 16-capstone-ai-platform/eks/namespace-rbac.yaml
# kubectl apply -f 16-capstone-ai-platform/eks/workflowtemplate-platform-e2e.yaml
# argo submit --watch -n ch15-pipelines --from workflowtemplate/platform-e2e

echo "Every command above is commented out on purpose — uncomment and run one phase at a time."
