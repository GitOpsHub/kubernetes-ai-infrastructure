#!/usr/bin/env bash
# Install the KubeRay operator (controller + CRDs for RayCluster/RayJob/RayService). Same on
# every cloud.
set -euo pipefail
: "${KUBERAY_VERSION:?source versions.env first}"

helm repo add kuberay https://ray-project.github.io/kuberay-helm/ --force-update
helm repo update kuberay

helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system --create-namespace \
  --version "${KUBERAY_VERSION}" \
  --wait --timeout 5m

kubectl -n kuberay-system rollout status deploy/kuberay-operator --timeout=5m
kubectl get crd rayclusters.ray.io rayjobs.ray.io rayservices.ray.io
