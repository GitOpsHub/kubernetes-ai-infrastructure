#!/usr/bin/env bash
# Remove chapter workloads. UNINSTALL_KSERVE=true also removes the KServe controller/CRDs
# (careful: this affects the whole cluster, not just this chapter's namespace).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE" --ignore-not-found || true
kubectl delete -k "$HERE/generative" --ignore-not-found || true
if [[ "${UNINSTALL_KSERVE:-false}" == "true" ]]; then
  helm -n kserve uninstall kserve || true
  helm -n kserve uninstall kserve-crd || true
fi
