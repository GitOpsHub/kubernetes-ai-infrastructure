#!/usr/bin/env bash
# Scale to 0 first so Karpenter's consolidateAfter fires and terminates the EC2 instances (Karpenter
# nodes are NOT part of any eksctl-managed ASG -- they disappear when Karpenter decides to, not
# when a node group is deleted). Verify in the EC2 console if you're not sure.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl -n ch13-autoscale scale deploy/scale-demo --replicas=0 2>/dev/null || true
kubectl delete -k "$HERE" --ignore-not-found || true
kubectl delete -f "$HERE/nodepool.yaml" --ignore-not-found || true
