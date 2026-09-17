#!/usr/bin/env bash
# Spot GPU managed node group for the Ray worker group only (L4: g6.xlarge / g6.2xlarge for spot
# diversification). The RayCluster head, RayJob's ephemeral cluster and RayService run on your
# existing on-demand default node group (from 00-prerequisites-and-cluster-setup).
# CAPACITY=on-demand creates the fallback group instead.
# Requires "All G and VT Spot Instance Requests" (or On-Demand G and VT) vCPU quota >= 8.
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
CAPACITY="${CAPACITY:-spot}"
if [[ "${CAPACITY}" == "spot" ]]; then NG=ch08-gpu-spot-l4; SPOT=true; else NG=ch08-gpu-ondemand-l4; SPOT=false; fi

cat <<YAML | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${EKS_CLUSTER}
  region: ${AWS_REGION}
managedNodeGroups:
  - name: ${NG}
    amiFamily: AmazonLinux2023
    instanceTypes: ["g6.xlarge", "g6.2xlarge"]
    spot: ${SPOT}
    minSize: 0
    desiredCapacity: 0
    maxSize: 2
    volumeSize: 100
    labels:
      ch08.lab/gpu: l4
    taints:
      - key: nvidia.com/gpu
        value: "true"
        effect: NoSchedule
    propagateASGTags: true
YAML
