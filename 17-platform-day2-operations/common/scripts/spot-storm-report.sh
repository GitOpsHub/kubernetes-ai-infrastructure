#!/usr/bin/env bash
# Spot-reclaim-storm runbook, step 1: read-only snapshot of how many nodes just disappeared at
# once, which workloads lost pods, and whether the fallback (on-demand ResourceFlavor / NodePool
# from chapters 06/13) is actually taking over -- vs. everything just queuing behind exhausted
# spot quota. Run this the moment you notice a wave of Pending pods or NotReady nodes.
set -euo pipefail

echo "== Nodes by phase (a storm shows several NotReady/gone within the same few minutes) =="
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,SPOT:.metadata.labels."cloud\.google\.com/gke-spot",AGE:.metadata.creationTimestamp

echo
echo "== Recent node-related events (Preempted/Deleted/NodeNotReady, clustered timestamps = a storm) =="
kubectl get events -A --field-selector reason=NodeNotReady --sort-by=.lastTimestamp | tail -20
kubectl get events -A --field-selector reason=Preempted --sort-by=.lastTimestamp 2>/dev/null | tail -20

echo
echo "== Pods currently Pending (the visible symptom) =="
kubectl get pods -A --field-selector status.phase=Pending -o wide

echo
echo "== Kueue Workloads waiting on capacity right now =="
kubectl get workloads -A 2>/dev/null | grep -v Admitted || echo "(none pending, or Kueue not installed)"

echo
echo "Next steps (README section 5):"
echo "  1. Confirm this is really a spot-wide event, not one flaky node: multiple nodes across"
echo "     different instance types/AZs going NotReady within the same few minutes = a storm."
echo "  2. Check the autoscaler is provisioning the fallback shape, not stuck retrying the same"
echo "     exhausted spot pool: 'kubectl get nodeclaims' (Karpenter/AKS NAP) or"
echo "     'kubectl get events --field-selector reason=TriggeredScaleUp' (GKE NAP)."
echo "  3. Kueue's waitForPodsReady (06-batch-jobs-and-kueue) should be requeuing half-admitted"
echo "     Workloads automatically -- if a Workload is stuck Admitted but never Running, that's"
echo "     the thing to page someone about, not the storm itself."
echo "  4. This is expected behavior for spot capacity, not an incident to 'fix' -- the postmortem"
echo "     question is whether PDBs/checkpointing/podFailurePolicy (chapters 06, 09) absorbed it"
echo "     without data loss, not why spot was reclaimed."
