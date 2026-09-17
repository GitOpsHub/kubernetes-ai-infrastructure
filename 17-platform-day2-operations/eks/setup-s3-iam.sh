#!/usr/bin/env bash
# Creates the Velero S3 bucket, an IAM role trusted by EKS Pod Identity, and the Pod Identity
# association for the "velero" ServiceAccount -- same pattern as
# 05-model-storage-and-data/eks/setup-s3-iam.sh, no static access keys.
set -euo pipefail
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}" "${AWS_ACCOUNT_ID:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NS=velero
SA=velero
BUCKET="${VELERO_S3_BUCKET:-${AWS_ACCOUNT_ID}-ch17-velero}"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
  aws s3api put-public-access-block --bucket "${BUCKET}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-versioning --bucket "${BUCKET}" --versioning-configuration Status=Enabled
fi

if ! aws eks describe-addon --cluster-name "${EKS_CLUSTER}" --addon-name eks-pod-identity-agent --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws eks create-addon --cluster-name "${EKS_CLUSTER}" --addon-name eks-pod-identity-agent --region "${AWS_REGION}"
fi

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

# Velero's documented least-privilege AWS policy for backup/restore + EBS snapshots.
cat > "${TMP}/policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:DescribeVolumes","ec2:DescribeSnapshots","ec2:CreateTags",
                 "ec2:CreateVolume","ec2:CreateSnapshot","ec2:DeleteSnapshot"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:DeleteObject","s3:PutObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::${BUCKET}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${BUCKET}"]
    }
  ]
}
JSON

ROLE="ch17-velero-${EKS_CLUSTER}"
if ! aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1; then
  aws iam create-role --role-name "${ROLE}" --assume-role-policy-document "file://${TMP}/trust.json"
fi
aws iam put-role-policy --role-name "${ROLE}" --policy-name velero-backup --policy-document "file://${TMP}/policy.json"
ROLE_ARN="$(aws iam get-role --role-name "${ROLE}" --query Role.Arn --output text)"

EXISTING="$(aws eks list-pod-identity-associations --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
  --namespace "${NS}" --service-account "${SA}" --query 'associations[0].associationId' --output text)"
if [[ "${EXISTING}" == "None" || -z "${EXISTING}" ]]; then
  aws eks create-pod-identity-association --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
    --namespace "${NS}" --service-account "${SA}" --role-arn "${ROLE_ARN}"
fi

printf '# written by setup-s3-iam.sh\nVELERO_S3_BUCKET=%s\n' "${BUCKET}" > "${HERE}/bucket.env"
echo "bucket s3://${BUCKET} ready for Velero; ${HERE}/bucket.env updated"
echo "Pod Identity association for ns=${NS} sa=${SA} -> ${ROLE_ARN} is in place. Note: the"
echo "'velero' namespace/ServiceAccount is created by install-velero.sh (Helm) -- run that next."
