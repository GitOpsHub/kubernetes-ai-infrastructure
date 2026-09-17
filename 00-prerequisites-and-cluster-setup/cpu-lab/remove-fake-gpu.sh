#!/usr/bin/env bash
# Undo advertise-fake-gpu.sh. Always run this when finished.
set -euo pipefail
: "${NODE:?set NODE=<node-name>}"
RESOURCE="${RESOURCE:-nvidia.com/gpu}"
ESCAPED="${RESOURCE//\//~1}"
kubectl patch node "$NODE" --subresource=status --type=json \
  -p "[{\"op\":\"remove\",\"path\":\"/status/capacity/${ESCAPED}\"}]" || true
kubectl label node "$NODE" fake-gpu- || true
kubectl taint node "$NODE" nvidia.com/gpu=present:NoSchedule- || true
kubectl get node "$NODE" -o jsonpath="{.status.capacity}{'\n'}"
