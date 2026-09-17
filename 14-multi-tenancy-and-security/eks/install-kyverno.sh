#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${KYVERNO_VERSION:=3.9.1}"   # VERIFY: see gke/install-kyverno.sh

helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm repo update kyverno
helm upgrade --install kyverno kyverno/kyverno \
  --version "${KYVERNO_VERSION}" \
  --namespace kyverno --create-namespace \
  --set admissionController.replicas=1 \
  --set backgroundController.enabled=true \
  --set reportsController.enabled=false

kubectl -n kyverno rollout status deployment/kyverno-admission-controller --timeout=180s
