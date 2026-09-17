#!/usr/bin/env bash
# Creates an EFS file system reachable from the cluster, installs the EFS CSI add-on and gives its
# controller (efs-csi-controller-sa) permission to manage access points via EKS Pod Identity.
# Cleanup (manual): delete mount targets, then `aws efs delete-file-system --file-system-id <id>`.
set -euo pipefail
: "${AWS_REGION:?source env.sh}" "${EKS_CLUSTER:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

VPC_ID="$(aws eks describe-cluster --name "${EKS_CLUSTER}" --region "${AWS_REGION}" --query cluster.resourcesVpcConfig.vpcId --output text)"
CLUSTER_SG="$(aws eks describe-cluster --name "${EKS_CLUSTER}" --region "${AWS_REGION}" --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)"
SUBNETS="$(aws eks describe-cluster --name "${EKS_CLUSTER}" --region "${AWS_REGION}" --query 'cluster.resourcesVpcConfig.subnetIds[]' --output text)"

FS_ID="$(aws efs create-file-system --region "${AWS_REGION}" --encrypted \
  --performance-mode generalPurpose --throughput-mode elastic \
  --tags "Key=Name,Value=${EKS_CLUSTER}-ch05-models" --query FileSystemId --output text)"
echo "created ${FS_ID}; waiting for it to become available"
until [[ "$(aws efs describe-file-systems --file-system-id "${FS_ID}" --region "${AWS_REGION}" --query 'FileSystems[0].LifeCycleState' --output text)" == "available" ]]; do sleep 5; done

# NFS (2049) from the cluster security group
EFS_SG="$(aws ec2 create-security-group --region "${AWS_REGION}" --vpc-id "${VPC_ID}" \
  --group-name "${EKS_CLUSTER}-ch05-efs" --description "EFS for ch05" --query GroupId --output text)"
aws ec2 authorize-security-group-ingress --region "${AWS_REGION}" --group-id "${EFS_SG}" \
  --protocol tcp --port 2049 --source-group "${CLUSTER_SG}"

# one mount target per AZ
SEEN_AZ=" "   # plain string, works with macOS bash 3.2
for s in ${SUBNETS}; do
  az="$(aws ec2 describe-subnets --subnet-ids "${s}" --region "${AWS_REGION}" --query 'Subnets[0].AvailabilityZone' --output text)"
  case "${SEEN_AZ}" in *" ${az} "*) continue ;; esac
  SEEN_AZ="${SEEN_AZ}${az} "
  aws efs create-mount-target --region "${AWS_REGION}" --file-system-id "${FS_ID}" \
    --subnet-id "${s}" --security-groups "${EFS_SG}"
done

# EFS CSI controller identity (Pod Identity) + add-on
cat > "${TMP}/trust.json" <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}
JSON
ROLE="ch05-efs-csi-${EKS_CLUSTER}"
aws iam get-role --role-name "${ROLE}" >/dev/null 2>&1 || \
  aws iam create-role --role-name "${ROLE}" --assume-role-policy-document "file://${TMP}/trust.json"
aws iam attach-role-policy --role-name "${ROLE}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy
ROLE_ARN="$(aws iam get-role --role-name "${ROLE}" --query Role.Arn --output text)"

aws eks create-addon --cluster-name "${EKS_CLUSTER}" --region "${AWS_REGION}" \
  --addon-name aws-efs-csi-driver \
  --pod-identity-associations "serviceAccount=efs-csi-controller-sa,roleArn=${ROLE_ARN}" || true

printf '# written by setup-efs.sh\nEFS_FILE_SYSTEM_ID=%s\n' "${FS_ID}" > "${HERE}/efs.env"
echo "EFS ${FS_ID} ready; ${HERE}/efs.env updated"
