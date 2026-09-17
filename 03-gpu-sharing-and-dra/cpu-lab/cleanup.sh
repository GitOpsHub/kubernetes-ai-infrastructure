#!/usr/bin/env bash
# Tear down the local kind DRA lab. Free (runs on your laptop, no cloud billing), but a
# leftover kind cluster still eats local CPU/RAM.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER="${CLUSTER:-dra-cpu-lab}"

kubectl --context "kind-${CLUSTER}" delete -k "${DIR}" --ignore-not-found --wait=false || true
helm --kube-context "kind-${CLUSTER}" uninstall dra-example-driver -n dra-example-driver 2>/dev/null || true
kind delete cluster --name "${CLUSTER}"
