#!/usr/bin/env bash
# Install Kubeflow Trainer (controller + JobSet dependency + CRDs) and the built-in
# torch-distributed ClusterTrainingRuntime. Same on every cloud.
set -euo pipefail
: "${KUBEFLOW_TRAINER_VERSION:?source versions.env first}"

helm upgrade --install kubeflow-trainer oci://ghcr.io/kubeflow/charts/kubeflow-trainer \
  --namespace kubeflow-system --create-namespace \
  --version "${KUBEFLOW_TRAINER_VERSION#v}" \
  --set runtimes.torchDistributed.enabled=true \
  --wait --timeout 10m

kubectl -n kubeflow-system rollout status deploy --timeout=5m
kubectl get crd trainjobs.trainer.kubeflow.org trainingruntimes.trainer.kubeflow.org clustertrainingruntimes.trainer.kubeflow.org
# The runtimes are applied by a post-install hook Job; give it a moment if this is empty.
kubectl get clustertrainingruntimes
