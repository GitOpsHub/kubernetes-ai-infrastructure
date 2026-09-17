#!/usr/bin/env bash
# Installs kubernetes-sigs/dra-example-driver, which advertises simulated GPUs (via ResourceSlice)
# per worker node and reports fake device info back through a plugin sidecar - no NVIDIA
# hardware/driver/image needed. Upstream ships no OCI/Helm-repo chart yet, so we clone the
# pinned tag and install the chart from the local checkout, exactly as its own docs do.
set -euo pipefail
DRA_EXAMPLE_DRIVER_VERSION="${DRA_EXAMPLE_DRIVER_VERSION:-v0.5.0}"   # not in versions.env yet
WORKDIR="${WORKDIR:-$(mktemp -d)}"

git clone --depth 1 --branch "${DRA_EXAMPLE_DRIVER_VERSION}" \
  https://github.com/kubernetes-sigs/dra-example-driver.git "${WORKDIR}/dra-example-driver"

helm upgrade --install dra-example-driver \
  "${WORKDIR}/dra-example-driver/deployments/helm/dra-example-driver" \
  --namespace dra-example-driver --create-namespace \
  --set image.repository=registry.k8s.io/dra-example-driver/dra-example-driver \
  --set image.tag="${DRA_EXAMPLE_DRIVER_VERSION}"

kubectl -n dra-example-driver rollout status daemonset/dra-example-driver-kubeletplugin --timeout=120s
kubectl get deviceclasses
kubectl get resourceslices -o wide
echo "Driver name: gpu.example.com (see: kubectl get resourceslice -o yaml)"
