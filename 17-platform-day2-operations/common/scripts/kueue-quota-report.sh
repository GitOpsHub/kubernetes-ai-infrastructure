#!/usr/bin/env bash
# Kueue quota-exhaustion runbook, step 1: read-only summary of every ClusterQueue's usage vs.
# quota and the oldest Pending Workload per queue -- the two facts you need before deciding
# "raise nominalQuota," "check for a stuck admitted-but-not-progressing Workload," or "this is
# working as designed, the team is just genuinely out of budget." Companion to
# 06-batch-jobs-and-kueue/README.md section 8 troubleshooting table.
set -euo pipefail

echo "== ClusterQueues: nominal quota vs. current usage per flavor =="
kubectl get clusterqueue -o json | \
  jq -r '.items[] | "\(.metadata.name)\t" + ((.status.flavorsUsage // []) | map("\(.name)=\(.resources[]?.total // "0")") | join(","))'

echo
echo "== Pending Workloads, oldest first (a long queue age is the symptom teams actually report) =="
kubectl get workloads -A -o json | \
  jq -r '.items[] | select(([.status.conditions[]? | select(.type=="Admitted" and .status=="True")] | length) == 0)
    | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.queueName)\t\(.metadata.creationTimestamp)"' | \
  sort -k4 | column -t

echo
echo "== Cohorts: which ClusterQueues are borrowing, and from whom =="
kubectl get cohort -o wide 2>/dev/null || echo "(no Cohort objects, or Kueue not installed)"

echo
echo "Next steps (README section 5):"
echo "  - A team stuck Pending with 'borrowing limit exceeded': raise borrowingLimit on their"
echo "    flavor, or their cohort-mate's nominalQuota, per 06-batch-jobs-and-kueue section 3.4-3.5."
echo "  - A team stuck Pending with quota available elsewhere in the cohort: check"
echo "    reclaimWithinCohort/borrowWithinCohort aren't set to Never (06-batch-jobs-and-kueue Q7)."
echo "  - Oldest-Pending age growing steadily, not just one spike: real capacity shortage --"
echo "    this is 13-node-autoscaling-and-cost's problem (add spot diversification/on-demand"
echo "    fallback), not a Kueue config problem."
