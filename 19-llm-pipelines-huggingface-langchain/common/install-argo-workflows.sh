#!/usr/bin/env bash
# Install (or extend) Argo Workflows so its controller manages the ch19-pipelines namespace.
# Called by every <cloud>/install.sh; safe to run on its own and to re-run.
#
# Three situations:
#   1. No Argo Workflows yet        -> helm install, watching only ch19-pipelines.
#   2. Installed with helm (ch15's cpu-lab/install-argo-workflows.sh) -> helm upgrade that keeps the
#      namespaces it already watches and ADDS ch19-pipelines (a plain --set would replace the list).
#   3. Managed by Argo CD (ch15's app-of-apps, Application "ch15-argo-workflows") -> do NOT helm
#      upgrade behind Argo CD's back (it would revert it on the next sync). The GitOps way: the
#      values file 15-mlops-gitops-and-pipelines/common/workflows/values-argo-workflows.yaml already
#      lists "- ch19-pipelines" under controller.workflowNamespaces in this repo -- make sure your
#      fork has that line, push, and let Argo CD sync. This script only prints that and exits
#      (FORCE_HELM=true overrides).
#
# What workflowNamespaces buys you (chart 2.0.6, singleNamespace=false): NOT what the controller
# watches -- it watches all namespaces through its ClusterRole. The list only decides where the
# chart creates its default workflow ServiceAccount "argo-workflow" + executor Role/RoleBinding.
# Our steps run as ServiceAccount pipeline-runner, whose executor RBAC ships in common/base, so
# listing ch19-pipelines is belt-and-braces (keeps it in line with ch15's GitOps values file).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
# Chart 2.0.6 == app v4.1.3. Falls back to the chart ch15 was written against if versions.env
# doesn't define it yet.
: "${ARGO_WORKFLOWS_VERSION:=2.0.6}"
ARGO_NS="${ARGO_NS:-argo}"
RELEASE="${ARGO_RELEASE:-argo-workflows}"
WF_NS=ch19-pipelines

command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (merges the existing workflowNamespaces list)" >&2; exit 1; }

if [[ "${FORCE_HELM:-false}" != "true" ]] && \
   kubectl -n argocd get applications.argoproj.io ch15-argo-workflows >/dev/null 2>&1; then
  cat <<MSG
Argo Workflows is managed by Argo CD (Application argocd/ch15-argo-workflows) -- not touching it.
GitOps path: make sure controller.workflowNamespaces in
  15-mlops-gitops-and-pipelines/common/workflows/values-argo-workflows.yaml
lists "- ${WF_NS}" (it does in this repo), commit + push to the repo Argo CD tracks, then:
  argocd app sync ch15-argo-workflows   (or wait for auto-sync)
Re-run with FORCE_HELM=true to helm-upgrade anyway (Argo CD will then show the app OutOfSync).
MSG
  exit 0
fi

# The chart creates RBAC objects in every watched namespace, so it must exist first.
kubectl create namespace "${WF_NS}" --dry-run=client -o yaml | kubectl apply -f -

# Union of what the release already watches + ch19-pipelines.
EXISTING="$(helm get values "${RELEASE}" -n "${ARGO_NS}" -o json 2>/dev/null \
  | jq -r '(.controller.workflowNamespaces // [])[]' || true)"
NAMESPACES="$(printf '%s\n%s\n' "${EXISTING}" "${WF_NS}" | sed '/^$/d' | sort -u | paste -sd, -)"
echo "Argo Workflows ${ARGO_WORKFLOWS_VERSION}: controller.workflowNamespaces={${NAMESPACES}}"

helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo update argo >/dev/null

# --reuse-values keeps whatever else an earlier install set (e.g. ch15's server flags);
# authModes=server = UI/CLI use the server's own identity: lab only, reach it with port-forward,
# never expose it (ch15 README covers SSO).
helm upgrade --install "${RELEASE}" argo/argo-workflows \
  --version "${ARGO_WORKFLOWS_VERSION}" \
  --namespace "${ARGO_NS}" --create-namespace \
  --reuse-values \
  --set "controller.workflowNamespaces={${NAMESPACES}}" \
  --set 'server.authModes={server}'

kubectl -n "${ARGO_NS}" rollout status "deployment/${RELEASE}-workflow-controller" --timeout=180s
kubectl get crd workflowtemplates.argoproj.io >/dev/null
echo "Argo Workflows ready. UI: kubectl -n ${ARGO_NS} port-forward svc/${RELEASE}-server 2746:2746"
