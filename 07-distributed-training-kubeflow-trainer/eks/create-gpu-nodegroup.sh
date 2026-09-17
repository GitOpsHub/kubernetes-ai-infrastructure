#!/usr/bin/env bash
# Spot GPU managed node group (L4: g6.xlarge / g6.2xlarge for spot diversification).
# CAPACITY=on-demand creates the fallback group instead.
# Requires "All G and VT Spot Instance Requests" (or On-Demand G and VT) vCPU quota >= 16.
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
CAPACITY="${CAPACITY:-spot}"
if [[ "${CAPACITY}" == "spot" ]]; then NG=gpu-spot-l4; SPOT=true; else NG=gpu-ondemand-l4; SPOT=false; fi

cat <<YAML | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${EKS_CLUSTER}
  region: ${AWS_REGION}
managedNodeGroups:
  - name: ${NG}
    amiFamily: AmazonLinux2023          # eksctl picks the NVIDIA AL2023 AMI for GPU instance types
    instanceTypes: ["g6.xlarge", "g6.2xlarge"]
    spot: ${SPOT}
    minSize: 0
    desiredCapacity: 0
    maxSize: 2
    volumeSize: 100                     # the PyTorch CUDA image is ~4 GB compressed
    labels:
      ch07.lab/gpu: l4
    taints:
      - key: nvidia.com/gpu
        value: "true"
        effect: NoSchedule
    propagateASGTags: true              # lets Cluster Autoscaler scale this group from zero
    # efaEnabled: true                  # advanced: only on EFA-capable types (p4d/p5/g6e.8xlarge+), see README
YAML
