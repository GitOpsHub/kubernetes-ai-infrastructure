#!/usr/bin/env bash
# cpu-lab prerequisites: Argo Workflows watching ch19-pipelines, and a check that chapter 09's
# cpu-lab Ollama (the LLM endpoint rag-api and the batch pipeline call) is deployed. No cloud CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"

"${HERE}/../common/install-argo-workflows.sh"

if kubectl -n ch09-vllm-cpu get deployment ollama >/dev/null 2>&1; then
  echo "found ch09-vllm-cpu/ollama -- rag-api and langchain-batch-inference will use it"
else
  echo "WARNING: ch09 cpu-lab Ollama not found. Deploy it first:"
  echo "  kubectl apply -k ${ROOT}/09-llm-inference-with-vllm/cpu-lab"
fi

cat <<NEXT

Next:
  ${HERE}/build-load-kind.sh      # CPU trainer image -> kind/minikube nodes -> images.env
  kubectl apply -k ${HERE}
NEXT
