#!/usr/bin/env bash
# Create/update the hf-token Secret from $HF_TOKEN (never committed, never inlined in a manifest).
# Qwen3-0.6B is ungated so this is optional for the base lab, but required once you swap in a
# gated model, and it silences anonymous-download rate limits either way.
#   HF_TOKEN=hf_xxx ./create-hf-secret.sh ch09-vllm
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${HF_TOKEN:?export HF_TOKEN=hf_xxx or set it in env.sh}"
NAMESPACE="${1:-ch09-vllm}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic hf-token \
  --namespace "$NAMESPACE" \
  --from-literal=HF_TOKEN="$HF_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
