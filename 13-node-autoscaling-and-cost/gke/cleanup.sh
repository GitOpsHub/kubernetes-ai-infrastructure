#!/usr/bin/env bash
# Scale scale-demo back to 0 first so NAP/CAS actually removes the node(s) it created, then
# remove the chapter's objects. NAP-created node pools self-delete once empty for
# `consolidationDelayMinutes` -- give it a few minutes before assuming something is stuck.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl -n ch13-autoscale scale deploy/scale-demo --replicas=0 2>/dev/null || true
kubectl delete -k "$HERE" --ignore-not-found || true
