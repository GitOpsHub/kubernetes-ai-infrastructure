#!/usr/bin/env bash
# Delete the chapter's Kubernetes objects (Workflows, WorkflowTemplates, Deployments, the PVC and
# the data on it, namespace). No cloud resources exist in cpu-lab.
#   DELETE_IMAGE=true ./cleanup.sh   -> also remove the local ch19-trainer:cpu docker image
# Argo Workflows (shared with chapter 15) and ch09's Ollama are left running.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl -n ch19-pipelines delete workflows.argoproj.io --all --ignore-not-found 2>/dev/null || true
kubectl delete -k "${HERE}" --ignore-not-found || true
if [[ "${DELETE_IMAGE:-false}" == "true" ]]; then
  docker image rm "${IMAGE:-ch19-trainer:cpu}" || true
fi
echo "ch19 cpu-lab removed. Argo Workflows: helm uninstall argo-workflows -n argo (if nothing else uses it)."
