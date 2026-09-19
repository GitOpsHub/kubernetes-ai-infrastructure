#!/usr/bin/env bash
# No Argo CD required: direct helm install, for any cluster (kind/minikube included). Mirrors
# what ../common/argocd-apps/apps-*/app-argo-workflows.yaml does declaratively once you have a
# live Argo CD to point at.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
source "$ROOT/versions.env"   # ARGO_WORKFLOWS_VERSION: chart 2.0.6 == app v4.1.3

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

helm upgrade --install argo-workflows argo/argo-workflows \
  --version "${ARGO_WORKFLOWS_VERSION}" \
  --namespace argo --create-namespace \
  --set server.extraArgs='{--auth-mode=server}' \
  --set controller.workflowNamespaces='{ch15-pipelines}'
# Only ch15-pipelines here on purpose (this lab's namespace). Chapter 19 ships its own installer
# (19-llm-pipelines-huggingface-langchain/*/install.sh) that re-runs this release with ch19-pipelines
# added; the GitOps path (../common/workflows/values-argo-workflows.yaml) already lists both.

kubectl -n argo rollout status deployment/argo-workflows-workflow-controller --timeout=180s
echo "Argo Workflows ${ARGO_WORKFLOWS_VERSION} installed. UI: kubectl -n argo port-forward svc/argo-workflows-server 2746:2746"
