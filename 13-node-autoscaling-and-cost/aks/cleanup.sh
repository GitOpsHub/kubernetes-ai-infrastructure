#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl -n ch13-autoscale scale deploy/scale-demo --replicas=0 2>/dev/null || true
kubectl delete -k "$HERE" --ignore-not-found || true
kubectl delete -f "$HERE/nodepool.yaml" --ignore-not-found || true
