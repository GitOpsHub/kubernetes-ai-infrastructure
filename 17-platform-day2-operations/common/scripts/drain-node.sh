#!/usr/bin/env bash
# Cordon + drain one node for planned maintenance, honoring PodDisruptionBudgets so a GPU workload
# with a PDB (09-llm-inference-with-vllm/common/pdb.yaml, or the kserve-pdb this chapter adds for
# chapter 11) gets a chance to keep minAvailable replicas up instead of all going down at once.
# This does NOT touch a live cluster on its own -- it only runs when you invoke it with a real node
# name, same read/mutate-only-what-you-ask-for shape as every other install.sh in this course.
#
# Usage: ./drain-node.sh <node-name> [--dry-run]
set -euo pipefail

NODE="${1:?usage: drain-node.sh <node-name> [--dry-run]}"
DRY_RUN="${2:-}"

echo "== 1/3: cordon (stop new pods scheduling here) =="
kubectl cordon "${NODE}"

echo
echo "== 2/3: what's currently running here (review before draining) =="
kubectl get pods -A --field-selector "spec.nodeName=${NODE}" \
  -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PDB-PROTECTED:.metadata.labels

echo
echo "== 3/3: drain =="
if [[ "${DRY_RUN}" == "--dry-run" ]]; then
  echo "(--dry-run) would run:"
  echo "kubectl drain ${NODE} --ignore-daemonsets --delete-emptydir-data --timeout=300s"
  exit 0
fi

# --ignore-daemonsets: DaemonSet pods (dcgm-exporter, device plugin, CNI, ...) are expected to be
#   on every node and don't block a drain by design.
# --delete-emptydir-data: needed if any pod here uses an emptyDir HF cache
#   (09-llm-inference-with-vllm's default, before the model-cache-pvc component) -- that data is
#   lost, which is the point: the replacement pod on a different node re-downloads it.
# No --force: a pod with no controller (bare Pod) will correctly BLOCK the drain rather than being
#   silently deleted -- investigate why a bare Pod is running on a GPU node before forcing it.
# PDB-blocked evictions retry automatically until they succeed or --timeout is hit; a stuck drain
#   past --timeout almost always means "PDB minAvailable can't be satisfied with only 1 node left" --
#   scale up first, or see README section 4 troubleshooting.
kubectl drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout=300s

echo
echo "Node ${NODE} drained. To bring it back into service later: kubectl uncordon ${NODE}"
