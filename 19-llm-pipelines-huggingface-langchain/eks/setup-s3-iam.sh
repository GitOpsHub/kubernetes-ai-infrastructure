#!/usr/bin/env bash
# Creates the chapter bucket, two IAM roles trusted by EKS Pod Identity -- pipeline-runner
# (read/write: Argo steps) and model-reader (read-only: vLLM) -- their Pod Identity associations,
# and the EKS add-ons the lab needs. Idempotent: re-run safely. Writes bucket.env.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}" "${AWS_ACCOUNT_ID:?}"

NS=ch19-pipelines
BUCKET="${S3_BUCKET:-${AWS_ACCOUNT_ID}-ch19-pipelines}"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

# --- bucket (same region as the cluster: no cross-region transfer cost, lowest latency) ---
if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
  aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

# --- add-ons: Pod Identity agent + Mountpoint for S3 CSI driver ---
for addon in eks-pod-identity-agent aws-mountpoint-s3-csi-driver; do
  if ! aws eks describe-addon --cluster-name "${EKS_CLUSTER}" --addon-name "${addon}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws eks create-addon --cluster-name "${EKS_CLUSTER}" --addon-name "${addon}" --region "${AWS_REGION}"
  fi
done

# --- trust policy for EKS Pod Identity ---
cat > "${TMP}/trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "pods.eks.amazonaws.com"},
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
JSON

# --- permission policies (Mountpoint's documented least-privilege actions) ---
# No s3:DeleteObject anywhere: nothing in this chapter deletes or overwrites objects.
cat > "${TMP}/model-reader.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::${BUCKET}"]},
    {"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::${BUCKET}/*"]}
  ]
}
JSON
cat > "${TMP}/pipeline-runner.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::${BUCKET}"]},
    {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"],
     "Resource": ["arn:aws:s3:::${BUCKET}/*"]}
  ]
}
JSON

for sa in pipeline-runner model-reader; do
  ROLE="ch19-${sa}-${EKS_CLUSTER}"
  if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
    aws iam create-role --role-name "${ROLE}" --assume-role-policy-document "file://${TMP}/trust.json" >/dev/null
  fi
  aws iam put-role-policy --role-name "${ROLE}" --policy-name s3-ch19 \
    --policy-document "file://${TMP}/${sa}.json"
  ROLE_ARN="$(aws iam get-role --role-name "${ROLE}" --query Role.Arn --output text)"

  EXISTING="$(aws eks list-pod-identity-associations --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
    --namespace "${NS}" --service-account "${sa}" --query 'associations[0].associationId' --output text)"
  if [[ "${EXISTING}" == "None" || -z "${EXISTING}" ]]; then
    aws eks create-pod-identity-association --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
      --namespace "${NS}" --service-account "${sa}" --role-arn "${ROLE_ARN}" >/dev/null
  fi
  echo "role ${ROLE} -> ${NS}/${sa}"
done

printf '# written by setup-s3-iam.sh\nS3_BUCKET=%s\n' "${BUCKET}" > "${HERE}/bucket.env"
echo "bucket s3://${BUCKET} ready; ${HERE}/bucket.env updated"
