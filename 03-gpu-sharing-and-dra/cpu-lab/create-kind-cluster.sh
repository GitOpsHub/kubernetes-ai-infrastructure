#!/usr/bin/env bash
# CPU-ONLY DRA lab: a local kind cluster running the upstream dra-example-driver
# (kubernetes-sigs/dra-example-driver), which simulates GPUs entirely in software.
# Same ResourceClaim/DeviceClass/ResourceClaimTemplate mechanics as the real NVIDIA DRA
# driver in ../common/dra, no GPU quota or hardware needed.
#
# K8s 1.35: DynamicResourceAllocation is GA and locked on -> resource.k8s.io/v1 works with
# no feature gates. Requires kind >= v0.30 (resource.k8s.io/v1 support) and Docker/Podman.
set -euo pipefail
CLUSTER="${CLUSTER:-dra-cpu-lab}"
# VERIFY: pin/refresh this digest against the current kindest/node release before use:
#   https://github.com/kubernetes-sigs/kind/releases
NODE_IMAGE="${NODE_IMAGE:-kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0}"

cat <<EOF | kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --wait 2m --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

kubectl cluster-info --context "kind-${CLUSTER}"
kubectl get nodes -o wide
echo "Next: ./install-example-driver.sh"
