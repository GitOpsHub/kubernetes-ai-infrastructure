#!/usr/bin/env bash
# Install the pinned NVIDIA device plugin (Helm). Do not combine with the GPU Operator (chapter 02) or the DRA driver on the same nodes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/versions.env"; [[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
CHART_VERSION="${DEVICE_PLUGIN_VERSION#v}"
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin --force-update
helm repo update nvdp
helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin --create-namespace \
  --version "$CHART_VERSION" \
  -f "$HERE/values-device-plugin.yaml"
kubectl -n nvidia-device-plugin get ds
