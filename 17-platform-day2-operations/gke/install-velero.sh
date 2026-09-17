#!/usr/bin/env bash
# Install Velero on GKE via the official Helm chart, pinned to the versions verified in this
# chapter's README (Velero app v1.18.2 / chart 12.2.0, velero-plugin-for-gcp v1.14.2).
# Credentials: Workload Identity Federation for GKE (no GSA key) -- run setup-gcs-iam.sh first,
# it binds the bucket to exactly the KSA this chart creates (namespace velero, SA name velero).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_ID:?source env.sh}"

if [[ ! -f "${HERE}/bucket.env" ]]; then
  echo "Run ./setup-gcs-iam.sh first (creates the bucket + Workload Identity binding)." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "${HERE}/bucket.env"

: "${VELERO_CHART_VERSION:?source versions.env}"
: "${VELERO_GCP_PLUGIN_VERSION:?source versions.env}"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm repo update vmware-tanzu

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  --version "${VELERO_CHART_VERSION}" \
  --set-string "configuration.backupStorageLocation[0].name=default" \
  --set-string "configuration.backupStorageLocation[0].provider=gcp" \
  --set-string "configuration.backupStorageLocation[0].bucket=${VELERO_GCS_BUCKET}" \
  --set-string "configuration.volumeSnapshotLocation[0].name=default" \
  --set-string "configuration.volumeSnapshotLocation[0].provider=gcp" \
  --set-string "configuration.volumeSnapshotLocation[0].config.snapshotLocation=${REGION}" \
  --set "credentials.useSecret=false" \
  --set-string "initContainers[0].name=velero-plugin-for-gcp" \
  --set-string "initContainers[0].image=velero/velero-plugin-for-gcp:${VELERO_GCP_PLUGIN_VERSION}" \
  --set-string "initContainers[0].volumeMounts[0].mountPath=/target" \
  --set-string "initContainers[0].volumeMounts[0].name=plugins" \
  --set "deployNodeAgent=true" \
  --set-string "serviceAccount.server.name=velero" \
  --wait --timeout 10m

echo
kubectl -n velero get pods
echo
echo "Confirm the BackupStorageLocation is healthy (may take ~1 min after install):"
echo "  kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'; echo"
echo "Expect: Available"
echo
echo "GKE CSI snapshots need a VolumeSnapshotClass labeled velero.io/csi-volumesnapshot-class=true"
echo "for the pd.csi.storage.gke.io driver -- check for one, create if missing:"
echo "  kubectl get volumesnapshotclass -l velero.io/csi-volumesnapshot-class=true"
