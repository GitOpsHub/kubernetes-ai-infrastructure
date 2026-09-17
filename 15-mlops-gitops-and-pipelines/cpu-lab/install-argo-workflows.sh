#!/usr/bin/env bash
# No Argo CD required: direct helm install, for any cluster (kind/minikube included). Mirrors
# what ../common/argocd-apps/apps-*/app-argo-workflows.yaml does declaratively once you have a
# live Argo CD to point at.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${ARGO_WORKFLOWS_VERSION:=2.0.6}"   # VERIFY: not in versions.env — chart 2.0.6 == app v4.1.3,
                                        # per https://artifacthub.io/packages/helm/argo/argo-workflows as of 2026-09-16.

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

helm upgrade --install argo-workflows argo/argo-workflows \
  --version "${ARGO_WORKFLOWS_VERSION}" \
  --namespace argo --create-namespace \
  --set server.extraArgs='{--auth-mode=server}' \
  --set controller.workflowNamespaces='{ch15-pipelines}'

kubectl -n argo rollout status deployment/argo-workflows-workflow-controller --timeout=180s
echo "Argo Workflows ${ARGO_WORKFLOWS_VERSION} installed. UI: kubectl -n argo port-forward svc/argo-workflows-server 2746:2746"
