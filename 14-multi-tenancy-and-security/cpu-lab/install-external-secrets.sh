#!/usr/bin/env bash
# No cloud IAM required: same Helm install as the cloud folders, but paired with the
# `kubernetes` provider ClusterSecretStore (clustersecretstore-fake.yaml) so you can see the
# whole ExternalSecret -> Secret reconcile loop on any cluster, including kind/minikube.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ESO_VERSION:=2.10.0}"   # VERIFY: see ../gke/install-external-secrets.sh

helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo update external-secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  --version "${ESO_VERSION}" \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true

kubectl -n external-secrets rollout status deployment/external-secrets --timeout=180s
