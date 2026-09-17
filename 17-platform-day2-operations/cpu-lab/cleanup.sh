#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -k "${HERE}/../common/opencost" --ignore-not-found
kubectl delete -k "${HERE}/../common/velero" --ignore-not-found
kubectl delete -k "${HERE}/../common" --ignore-not-found

helm uninstall opencost -n opencost 2>/dev/null || true
kubectl delete namespace opencost --ignore-not-found

helm uninstall velero -n velero 2>/dev/null || true
kubectl delete namespace velero --ignore-not-found   # also removes the lab-only MinIO Deployment/Service/Secret

echo "cpu-lab teardown complete -- MinIO's emptyDir means there's no external bucket to clean up."
