#!/usr/bin/env bash
# Create the spot GPU managed node group (INCLUDE=ondemand-gpu for the fallback). Existing groups are skipped.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
export AWS_REGION EKS_CLUSTER
INCLUDE="${INCLUDE:-spot-gpu}"
envsubst '${EKS_CLUSTER} ${AWS_REGION}' < "$HERE/gpu-nodegroups.yaml" > "$HERE/.gpu-nodegroups.rendered.yaml"
eksctl create nodegroup -f "$HERE/.gpu-nodegroups.rendered.yaml" --include "$INCLUDE" --install-nvidia-plugin=false
eksctl get nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION"
