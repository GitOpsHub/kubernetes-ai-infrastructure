#!/usr/bin/env bash
# LAB ONLY. Advertise a fake extended resource on a CPU node by patching node *status*
# (Kubernetes docs: "Advertise Extended Resources for a Node").
# The scheduler will then place pods that request it on this node. No GPU exists: containers get
# no device, no driver, no /dev/nvidia*. It only teaches scheduling/accounting.
#
# Usage: NODE=<node-name> [COUNT=2] [RESOURCE=nvidia.com/gpu] ./advertise-fake-gpu.sh
set -euo pipefail
: "${NODE:?set NODE=<node-name> (kubectl get nodes)}"
COUNT="${COUNT:-2}"
RESOURCE="${RESOURCE:-nvidia.com/gpu}"
# JSON Pointer escaping: "/" in the resource name becomes "~1"
ESCAPED="${RESOURCE//\//~1}"

# Safety: refuse to touch a node that has a real GPU pool label.
if kubectl get node "$NODE" -o jsonpath='{.metadata.labels}' | grep -qE 'gke-accelerator|nvidia.com/gpu.present|workload":"gpu'; then
  echo "Refusing: $NODE looks like a real GPU node."; exit 1
fi

# Option A (kubectl >= 1.24): patch the status subresource directly.
kubectl patch node "$NODE" --subresource=status --type=json \
  -p "[{\"op\":\"add\",\"path\":\"/status/capacity/${ESCAPED}\",\"value\":\"${COUNT}\"}]"

# Option B (exactly as in the upstream docs):
#   kubectl proxy &
#   curl --header "Content-Type: application/json-patch+json" --request PATCH \
#     --data '[{"op":"add","path":"/status/capacity/nvidia.com~1gpu","value":"2"}]' \
#     http://localhost:8001/api/v1/nodes/$NODE/status

# Label + taint the node like a real GPU node so the drill mirrors production placement rules.
kubectl label node "$NODE" fake-gpu=true --overwrite
kubectl taint node "$NODE" nvidia.com/gpu=present:NoSchedule --overwrite

sleep 2
kubectl get node "$NODE" -o jsonpath="{.status.capacity}{'\n'}{.status.allocatable}{'\n'}"
