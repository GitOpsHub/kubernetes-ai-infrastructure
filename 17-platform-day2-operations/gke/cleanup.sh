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

echo "Cluster-side objects removed. The GCS bucket (gs://\$VELERO_GCS_BUCKET) and its backup"
echo "contents are NOT deleted by this script -- backups should outlive the cluster that made them."
echo "Delete it explicitly once you no longer need any of these backups:"
echo "  source ./bucket.env && gcloud storage rm -r gs://\${VELERO_GCS_BUCKET}"
