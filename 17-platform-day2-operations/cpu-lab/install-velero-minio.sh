#!/usr/bin/env bash
# Velero against a local, in-cluster MinIO instance instead of a real cloud bucket -- Velero's own
# documented pattern for testing/CI (see "Run Velero on your workstation without a cloud provider"
# in the Velero contrib examples). No cloud IAM, no real bucket: everything here runs on any
# cluster (kind, a spot CPU pool, whatever), and every backup is lost when MinIO's PVC is deleted --
# this validates the Velero/Schedule/Backup *mechanics*, not real durability (see README section 7
# "what doesn't carry over" for the cpu-lab).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${VELERO_CHART_VERSION:?source versions.env}"
: "${VELERO_AWS_PLUGIN_VERSION:?source versions.env}"   # the aws plugin also speaks the S3-compatible MinIO API
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"   # lab-only, throwaway credential -- never reuse in a real cluster

kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n velero -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  labels: {app: minio}
spec:
  replicas: 1
  selector: {matchLabels: {app: minio}}
  template:
    metadata: {labels: {app: minio}}
    spec:
      containers:
      - name: minio
        image: minio/minio:latest   # lab-only throwaway MinIO, deliberately unpinned (not in versions.env -- this is a disposable test double, not a component this course teaches); pin an explicit RELEASE.* tag if you keep this around
        args: ["server", "/data"]
        env:
        - {name: MINIO_ROOT_USER, value: "minioadmin"}
        - {name: MINIO_ROOT_PASSWORD, value: "minioadmin"}
        ports: [{containerPort: 9000}]
        volumeMounts: [{name: data, mountPath: /data}]
      volumes:
      - name: data
        emptyDir: {}   # lab-only: backups do not survive a MinIO pod restart, by design
---
apiVersion: v1
kind: Service
metadata: {name: minio, labels: {app: minio}}
spec:
  selector: {app: minio}
  ports: [{port: 9000, targetPort: 9000}]
YAML

kubectl -n velero wait --for=condition=available deploy/minio --timeout=120s

kubectl -n velero create secret generic minio-credentials \
  --from-literal=cloud="[default]
aws_access_key_id=${MINIO_ROOT_USER}
aws_secret_access_key=${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create the bucket via the S3 API (MinIO auto-creates on first PutObject too, but this makes the
# BackupStorageLocation come up Available immediately instead of racing MinIO's cold start).
kubectl -n velero run mc-bucket-init --rm -i --restart=Never --image=minio/mc:latest -- \
  sh -c "mc alias set local http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} && mc mb -p local/velero" \
  || echo "(bucket may already exist -- continuing)"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm repo update vmware-tanzu

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --version "${VELERO_CHART_VERSION}" \
  --set-string "configuration.backupStorageLocation[0].name=default" \
  --set-string "configuration.backupStorageLocation[0].provider=aws" \
  --set-string "configuration.backupStorageLocation[0].bucket=velero" \
  --set-string "configuration.backupStorageLocation[0].config.region=minio" \
  --set-string "configuration.backupStorageLocation[0].config.s3ForcePathStyle=true" \
  --set-string "configuration.backupStorageLocation[0].config.s3Url=http://minio.velero.svc:9000" \
  --set "credentials.useSecret=true" \
  --set-string "credentials.existingSecret=minio-credentials" \
  --set-string "initContainers[0].name=velero-plugin-for-aws" \
  --set-string "initContainers[0].image=velero/velero-plugin-for-aws:${VELERO_AWS_PLUGIN_VERSION}" \
  --set-string "initContainers[0].volumeMounts[0].mountPath=/target" \
  --set-string "initContainers[0].volumeMounts[0].name=plugins" \
  --set "deployNodeAgent=true" \
  --wait --timeout 10m

echo
kubectl -n velero get pods
echo
echo "Confirm the BackupStorageLocation is healthy:"
echo "  kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'; echo"
echo "Expect: Available"
echo "No cloud CSI driver here to snapshot volumes from -- this cpu-lab exercises the"
echo "Backup/Schedule/restore workflow against Kubernetes objects, not real PVC data snapshots"
echo "(defaultVolumesToFsBackup stays false; there's no CSI VolumeSnapshotClass without a cloud)."
