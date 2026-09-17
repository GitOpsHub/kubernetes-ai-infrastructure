#!/usr/bin/env bash
# Cluster-scoped prerequisite for the multinode-lws component: installs the LeaderWorkerSet
# controller (CRD + controller-manager in the lws-system namespace).
#   ./install-lws.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/versions.env"

echo "Installing LeaderWorkerSet ${LWS_VERSION}..."
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/lws/releases/download/${LWS_VERSION}/manifests.yaml"

kubectl wait --for=condition=Available --timeout=120s \
  -n lws-system deployment/lws-controller-manager
echo "LeaderWorkerSet installed in namespace lws-system."
