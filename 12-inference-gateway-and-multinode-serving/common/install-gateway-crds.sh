#!/usr/bin/env bash
# Cluster-scoped prerequisite, run ONCE per cluster before any overlay: installs the core
# Gateway API CRDs (standard channel) and the Gateway API Inference Extension CRDs
# (InferencePool, InferenceObjective). These are CRDs only -- no controller/EPP -- the
# controller comes from your cloud's Gateway implementation (gke/eks/aks install scripts) and
# the EPP Deployment lives in common/inferencepool (applied by kubectl apply -k).
#
#   ./install-gateway-crds.sh
#
# Versions pinned from ../../versions.env: GATEWAY_API_VERSION, GAIE_VERSION.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"

echo "Installing Gateway API ${GATEWAY_API_VERSION} (standard channel CRDs)..."
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "Installing Gateway API Inference Extension ${GAIE_VERSION} CRDs..."
# VERIFY: exact release-asset filename. Confirmed pattern (same layout as LWS releases) is
#   https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/<tag>/manifests.yaml
# If that 404s, install just the CRDs via the published Helm chart instead:
#   helm template epp-crds oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
#     --version "${GAIE_VERSION}" --show-only crds/* | kubectl apply --server-side -f -
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/manifests.yaml" # VERIFY

kubectl wait --for=condition=Established --timeout=60s \
  crd/inferencepools.inference.networking.k8s.io
echo "Gateway API + Inference Extension CRDs installed."
