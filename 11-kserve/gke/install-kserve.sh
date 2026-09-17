#!/usr/bin/env bash
# Install KServe CRDs + controller via the official OCI Helm charts, pinned to ${KSERVE_VERSION}.
# Standard (a.k.a. RawDeployment-capable) mode: plain Kubernetes Deployments/Services, no Knative
# or Istio dependency. LLMInferenceService's router still needs Gateway API CRDs + an
# implementation (see 12-inference-gateway-and-multinode-serving) for the route/gateway objects to
# actually come up — install those first if you're doing the generative/ lab.
# # VERIFY: chart names/flags against `helm show values oci://ghcr.io/kserve/charts/kserve-resources
# --version ${KSERVE_VERSION}` for your exact pinned version before relying on this in a real setup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"

helm upgrade --install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version "${KSERVE_VERSION}" \
  --namespace kserve --create-namespace \
  --wait

helm upgrade --install kserve oci://ghcr.io/kserve/charts/kserve-resources \
  --version "${KSERVE_VERSION}" \
  --namespace kserve \
  --set kserve.controller.deploymentMode=Standard \
  --wait --timeout 10m

kubectl -n kserve get pods
kubectl get crd | grep serving.kserve.io
