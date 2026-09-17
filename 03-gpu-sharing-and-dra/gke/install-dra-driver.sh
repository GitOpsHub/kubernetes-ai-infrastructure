#!/usr/bin/env bash
# Install the NVIDIA DRA driver (kubernetes-sigs/dra-driver-nvidia-gpu) on GKE.
# The project moved from NVIDIA/k8s-dra-driver-gpu to kubernetes-sigs; the chart is now
# published at registry.k8s.io with 0.x versions (older docs show nvidia/nvidia-dra-driver-gpu 25.x).
set -euo pipefail

DRA_DRIVER_NVIDIA_VERSION="${DRA_DRIVER_NVIDIA_VERSION:-0.5.0}"   # not in versions.env yet

helm upgrade --install nvidia-dra-driver-gpu \
  oci://registry.k8s.io/dra-driver-nvidia/charts/dra-driver-nvidia-gpu \
  --version "${DRA_DRIVER_NVIDIA_VERSION}" \
  --namespace nvidia-dra-driver-gpu --create-namespace \
  --set gpuResourcesEnabledOverride=true \
  --set resources.computeDomains.enabled=false \
  --set nvidiaDriverRoot=/home/kubernetes/bin/nvidia \
  --set featureGates.TimeSlicingSettings=true \
  --set featureGates.MPSSupport=true \
  --set kubeletPlugin.priorityClassName="" \
  --set controller.priorityClassName=""
# VERIFY: upstream's GKE demo clears priorityClassName because GKE limits system-node-critical
# pods outside kube-system via ResourceQuota; remove the two lines above if your cluster allows it.
# COS path per upstream docs: /home/kubernetes/bin/nvidia (Ubuntu node images: /opt/nvidia).

kubectl get deviceclass
kubectl get resourceslices -o wide
