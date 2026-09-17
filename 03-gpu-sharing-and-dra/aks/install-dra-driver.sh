#!/usr/bin/env bash
# Install the NVIDIA DRA driver on AKS, assuming the GPU Operator (chapter 02) owns the driver
# install (node pool created with --gpu-driver none). nvidiaDriverRoot points at the operator's
# driver container mount, not the host path AKS's own --gpu-driver Install would use.
# VERIFY: /run/nvidia/driver is the NVIDIA GPU Operator's standard driver root and matches the
# AKS engineering blog's DRA+MIG walkthrough; confirm against your operator's `driver.env` if
# you changed operator defaults in chapter 02.
set -euo pipefail
DRA_DRIVER_NVIDIA_VERSION="${DRA_DRIVER_NVIDIA_VERSION:-0.5.0}"   # not in versions.env yet

helm upgrade --install nvidia-dra-driver-gpu \
  oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu \
  --version "${DRA_DRIVER_NVIDIA_VERSION}" \
  --namespace nvidia-dra-driver-gpu --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set resources.computeDomains.enabled=false \
  --set nvidiaDriverRoot=/run/nvidia/driver \
  --set featureGates.TimeSlicingSettings=true \
  --set featureGates.MPSSupport=true \
  --set-json 'kubeletPlugin.nodeSelector={"gpu-mode":"dra"}'
# The nodeSelector keeps the DRA kubelet plugin OFF the device-plugin node pools
# (label set in create-nodepool-share.sh / create-nodepool-mig.sh). Never let the DRA driver
# and the device plugin share a node.

kubectl get deviceclass
kubectl get resourceslices -o wide
