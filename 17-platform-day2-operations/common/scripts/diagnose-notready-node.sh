#!/usr/bin/env bash
# Node-stuck-NotReady runbook, step 1: gather everything you need to tell "kubelet lost contact
# briefly" from "this node is actually dead" from "the GPU driver DaemonSet wedged it" -- read-only,
# safe to run against a live cluster at any time.
#
# Usage: ./diagnose-notready-node.sh <node-name>
set -euo pipefail
NODE="${1:?usage: diagnose-notready-node.sh <node-name>}"

echo "== Node conditions (look for Ready=Unknown vs Ready=False, and the lastTransitionTime) =="
kubectl get node "${NODE}" -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.lastTransitionTime}{"\t"}{.message}{"\n"}{end}'

echo
echo "== Node events (kubelet flapping, disk pressure, image GC, etc.) =="
kubectl get events -A --field-selector "involvedObject.name=${NODE}" --sort-by=.lastTimestamp | tail -30

echo
echo "== Pods still assigned to this node =="
kubectl get pods -A --field-selector "spec.nodeName=${NODE}" -o wide

echo
echo "== GPU Operator components on this node (if any) -- a wedged driver DaemonSet is a common =="
echo "== cause of a GPU node specifically going NotReady after a reboot/reclaim replacement     =="
kubectl get pods -n gpu-operator -o wide 2>/dev/null | awk -v n="${NODE}" 'NR==1 || $7==n'

echo
echo "Interpretation guide (README section 5):"
echo "  Ready=Unknown, recent lastTransitionTime  -> kubelet/network blip, often self-heals in minutes"
echo "  Ready=False, DiskPressure/MemoryPressure   -> real resource exhaustion on the node"
echo "  No recent kubelet heartbeat at all          -> check the cloud console: is the VM actually running?"
echo "  gpu-operator pods CrashLoopBackOff on this node -> see 02-nvidia-gpu-operator/README.md section 6"
echo "If the node doesn't recover within your maintenance window: cordon it (do NOT drain a node the"
echo "API server can't reach -- eviction requests to a dead kubelet just hang), then let the cluster"
echo "autoscaler/Karpenter/NAP replace it (13-node-autoscaling-and-cost) and delete the stale Node"
echo "object once the cloud confirms the underlying VM is gone: kubectl delete node ${NODE}"
