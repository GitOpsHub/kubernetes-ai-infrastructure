#!/usr/bin/env bash
# Read-only post-install checks, cloud-agnostic. Run after any cloud's install.sh.
set -euo pipefail

echo "== ClusterPolicy status ==" # Ready only once every enabled operand's DaemonSet/Deployment is up
kubectl get clusterpolicy cluster-policy -o jsonpath='{.status.state}{"\n"}'

echo "== gpu-operator pods =="
kubectl -n gpu-operator get pods -o wide

echo "== GPU capacity on nodes (device plugin registered) =="
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPUS:.status.allocatable.nvidia\\.com/gpu

echo "== GFD labels (present once gpu-feature-discovery has run on a GPU node) =="
kubectl get nodes -L nvidia.com/gpu.product,nvidia.com/gpu.memory,nvidia.com/gpu.count,nvidia.com/cuda.driver.major

echo "== Operator's own validator pods (must all be Completed) =="
kubectl -n gpu-operator get pods -l app=nvidia-operator-validator
kubectl -n gpu-operator get pods -l app.kubernetes.io/component=nvidia-driver -o wide 2>/dev/null || true

echo "== Smoke test: reuse chapter 01's CUDA job/pod against the Operator-managed nodes =="
echo "  kubectl apply -k 01-gpu-nodes-and-scheduling/<cloud>"
echo "  kubectl -n ch01-gpu logs job/cuda-vectoradd"
