#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl delete -k "$HERE/../common/servicemonitor" --ignore-not-found || true
kubectl delete -k "$HERE/../common/alerts" --ignore-not-found || true
kubectl delete -k "$HERE/../common/dashboards" --ignore-not-found || true
kubectl delete -k "$HERE/gmp" --ignore-not-found || true
helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found --wait=false
