#!/usr/bin/env bash
# NVIDIA DRA driver on EKS (K8s 1.34+, managed node groups / self-managed / Karpenter static
# capacity; NOT EKS Auto Mode). AL2023 NVIDIA AMI -> driver on the host -> nvidiaDriverRoot=/.
set -euo pipefail
DRA_DRIVER_NVIDIA_VERSION="${DRA_DRIVER_NVIDIA_VERSION:-0.5.0}"   # not in versions.env yet

helm upgrade --install nvidia-dra-driver-gpu \
  oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu \
  --version "${DRA_DRIVER_NVIDIA_VERSION}" \
  --namespace nvidia-dra-driver-gpu --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set resources.computeDomains.enabled=false \
  --set nvidiaDriverRoot=/ \
  --set featureGates.TimeSlicingSettings=true \
  --set featureGates.MPSSupport=true \
  --set-json 'kubeletPlugin.nodeSelector={"gpu-mode":"dra"}'
# The nodeSelector keeps the DRA kubelet plugin OFF the device-plugin node groups
# (label set in nodegroups.yaml). Never let DRA driver and device plugin share a node.

kubectl get deviceclass
kubectl get resourceslices -o wide
