#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -k "${HERE}/../common/opencost" --ignore-not-found
kubectl delete -k "${HERE}/../common/velero" --ignore-not-found
kubectl delete -k "${HERE}/../common/kserve-pdb" --ignore-not-found
kubectl delete -k "${HERE}/../common" --ignore-not-found

helm uninstall opencost -n opencost 2>/dev/null || true
kubectl delete namespace opencost --ignore-not-found

helm uninstall velero -n velero 2>/dev/null || true
kubectl delete namespace velero --ignore-not-found

echo "Cluster-side objects removed. The storage account/container (\$AZ_VELERO_STORAGE_ACCOUNT)"
echo "and its backup contents are NOT deleted by this script -- backups should outlive the"
echo "cluster that made them. Delete it explicitly once you no longer need any of these backups:"
echo "  source ./bucket.env && az storage account delete -n \${AZ_VELERO_STORAGE_ACCOUNT} -g \${AZ_VELERO_RESOURCE_GROUP} --yes"
