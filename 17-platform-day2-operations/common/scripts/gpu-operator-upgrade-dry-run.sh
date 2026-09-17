#!/usr/bin/env bash
# GPU driver / GPU Operator upgrade runbook, step 0: render the CURRENT and TARGET
# ${GPU_OPERATOR_VERSION} ClusterPolicy client-side and diff them, before touching a real cluster.
# Reuses 02-nvidia-gpu-operator's own values-<cloud>.yaml so the diff reflects this course's actual
# per-cloud toggles (driver/toolkit disabled on GKE/EKS, full stack on AKS -- see
# 02-nvidia-gpu-operator/README.md section 3.3), not a generic chart diff.
#
# Usage: ./gpu-operator-upgrade-dry-run.sh <cloud: gke|eks|aks> <target-version, e.g. v26.8.0>
set -euo pipefail

CLOUD="${1:?usage: gpu-operator-upgrade-dry-run.sh <gke|eks|aks> <target-version>}"
TARGET_VERSION="${2:?target GPU_OPERATOR_VERSION, e.g. v26.8.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CH02="${ROOT}/02-nvidia-gpu-operator"
# shellcheck disable=SC1091
source "${ROOT}/versions.env"
CURRENT_VERSION="${GPU_OPERATOR_VERSION}"
VALUES="${CH02}/${CLOUD}/values-${CLOUD}.yaml"

if [[ ! -f "${VALUES}" ]]; then
  echo "no values file at ${VALUES} -- CLOUD must be gke, eks or aks" >&2
  exit 1
fi

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update >/dev/null
helm repo update nvidia >/dev/null

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

echo "Rendering current  (${CURRENT_VERSION}) ClusterPolicy for ${CLOUD}..."
helm template gpu-operator nvidia/gpu-operator --version "${CURRENT_VERSION#v}" \
  -n gpu-operator -f "${VALUES}" > "${TMP}/current.yaml"

echo "Rendering target   (${TARGET_VERSION}) ClusterPolicy for ${CLOUD}..."
helm template gpu-operator nvidia/gpu-operator --version "${TARGET_VERSION#v}" \
  -n gpu-operator -f "${VALUES}" > "${TMP}/target.yaml"

echo
echo "== diff (current -> target) =="
diff -u "${TMP}/current.yaml" "${TMP}/target.yaml" || true

echo
echo "Before rolling this out to a real cluster (README section 3):"
echo "  1. Read the target release's notes for a driver-version bump (nearly every release ships one)."
echo "  2. Check the diff above for changed default driver/toolkit/dcgm-exporter image tags."
echo "  3. Roll out to ONE node pool/nodegroup first -- the driver DaemonSet restarts in place on"
echo "     an upgrade, which interrupts any GPU workload on that node."
echo "  4. Take a pre-upgrade Velero backup: common/velero/backup-manual-example.yaml, or"
echo "     'velero backup create pre-gpu-operator-upgrade --from-schedule=platform-daily'."
