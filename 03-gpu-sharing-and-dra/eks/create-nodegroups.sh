#!/usr/bin/env bash
# Create the chapter 03 GPU node groups. --install-nvidia-plugin=false because the GPU Operator
# (chapter 02) owns the device plugin; a second static plugin would double-advertise GPUs.
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?source env.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ONLY="${1:-gpu-share-spot}"   # gpu-share-spot | gpu-dra-spot | gpu-mig-spot

sed -e "s/__EKS_CLUSTER__/${EKS_CLUSTER}/" -e "s/__AWS_REGION__/${AWS_REGION}/" \
  "${DIR}/nodegroups.yaml" > "${DIR}/.nodegroups.rendered.yaml"

eksctl create nodegroup -f "${DIR}/.nodegroups.rendered.yaml" \
  --include "${ONLY}" \
  --install-nvidia-plugin=false
