#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"

kubectl delete -k "$(dirname "${BASH_SOURCE[0]}")" --ignore-not-found
helm uninstall external-secrets -n external-secrets --ignore-not-found 2>/dev/null || true
helm uninstall kyverno -n kyverno --ignore-not-found 2>/dev/null || true
kubectl delete namespace external-secrets kyverno --ignore-not-found
echo "ch14 namespaces, policies, ESO and Kyverno removed. IAM bindings created in setup-workload-identity.sh are NOT removed by this script — clean those up in the cloud console/CLI yourself."
