#!/usr/bin/env bash
# External Secrets Operator: pulls real secrets from Google Secret Manager into Kubernetes
# Secrets via a ClusterSecretStore, instead of committing them (or their values) anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
source "$ROOT/versions.env"
: "${PROJECT_ID:?set in env.sh}"
: "${ESO_VERSION:=2.10.0}"   # VERIFY: not in versions.env yet — pinned here against
                              # https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets
                              # (chart 2.10.0 == app v2.10.0) as of 2026-09-16.

helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  --version "${ESO_VERSION}" \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.annotations."iam\.gke\.io/gcp-service-account"="eso-secretmanager@${PROJECT_ID}.iam.gserviceaccount.com"

kubectl -n external-secrets rollout status deployment/external-secrets --timeout=180s
echo "External Secrets Operator ${ESO_VERSION} installed. Next: ./setup-workload-identity.sh, then apply clustersecretstore-gcp.yaml"
