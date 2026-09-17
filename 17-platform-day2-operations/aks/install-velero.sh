#!/usr/bin/env bash
# Install Velero on AKS via the official Helm chart, pinned to the versions verified in this
# chapter's README (Velero app v1.18.2 / chart 12.2.0, velero-plugin-for-microsoft-azure v1.14.2).
# Credentials: Azure Workload Identity (run setup-blob-iam.sh first) -- no storage account key,
# no service-principal secret. The AZURE_CLIENT_ID/TENANT_ID/FEDERATED_TOKEN_FILE env vars the
# plugin needs are injected automatically by AKS's workload-identity mutating webhook once the pod
# carries label azure.workload.identity/use=true and its ServiceAccount has the client-id
# annotation -- both set below.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${HERE}/bucket.env" ]]; then
  echo "Run ./setup-blob-iam.sh first (creates the storage account + Workload Identity binding)." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "${HERE}/bucket.env"

: "${VELERO_CHART_VERSION:?source versions.env}"
: "${VELERO_AZURE_PLUGIN_VERSION:?source versions.env}"

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
cat > "${TMP}/values-workload-identity.yaml" <<EOF
podLabels:
  azure.workload.identity/use: "true"
serviceAccount:
  server:
    name: velero
    annotations:
      azure.workload.identity/client-id: "${AZ_VELERO_MI_CLIENT_ID}"
EOF

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm repo update vmware-tanzu

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  --version "${VELERO_CHART_VERSION}" \
  -f "${TMP}/values-workload-identity.yaml" \
  --set-string "configuration.backupStorageLocation[0].name=default" \
  --set-string "configuration.backupStorageLocation[0].provider=azure" \
  --set-string "configuration.backupStorageLocation[0].bucket=${AZ_VELERO_CONTAINER}" \
  --set-string "configuration.backupStorageLocation[0].config.resourceGroup=${AZ_VELERO_RESOURCE_GROUP}" \
  --set-string "configuration.backupStorageLocation[0].config.storageAccount=${AZ_VELERO_STORAGE_ACCOUNT}" \
  --set-string "configuration.backupStorageLocation[0].config.subscriptionId=${AZ_VELERO_SUBSCRIPTION_ID}" \
  --set-string "configuration.volumeSnapshotLocation[0].name=default" \
  --set-string "configuration.volumeSnapshotLocation[0].provider=azure" \
  --set-string "configuration.volumeSnapshotLocation[0].config.resourceGroup=${AZ_VELERO_RESOURCE_GROUP}" \
  --set-string "configuration.volumeSnapshotLocation[0].config.subscriptionId=${AZ_VELERO_SUBSCRIPTION_ID}" \
  --set "credentials.useSecret=false" \
  --set-string "initContainers[0].name=velero-plugin-for-microsoft-azure" \
  --set-string "initContainers[0].image=velero/velero-plugin-for-microsoft-azure:${VELERO_AZURE_PLUGIN_VERSION}" \
  --set-string "initContainers[0].volumeMounts[0].mountPath=/target" \
  --set-string "initContainers[0].volumeMounts[0].name=plugins" \
  --set "deployNodeAgent=true" \
  --wait --timeout 10m

echo
kubectl -n velero get pods
echo
echo "Confirm the BackupStorageLocation is healthy (may take ~1 min after install):"
echo "  kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'; echo"
echo "Expect: Available"
echo
echo "AKS CSI snapshots need a VolumeSnapshotClass labeled velero.io/csi-volumesnapshot-class=true"
echo "for the disk.csi.azure.com driver -- check for one, create if missing:"
echo "  kubectl get volumesnapshotclass -l velero.io/csi-volumesnapshot-class=true"
