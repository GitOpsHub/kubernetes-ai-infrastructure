#!/usr/bin/env bash
# IRSA (IAM Roles for Service Accounts) — same "no downloaded key" pattern as GKE Workload
# Identity, via the cluster's OIDC provider instead. Requires
#   eksctl utils associate-iam-oidc-provider --cluster "$EKS_CLUSTER" --approve
# to already be done (chapter 00 sets this up for the whole cluster).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${EKS_CLUSTER:?set in env.sh}"
: "${AWS_REGION:?set in env.sh}"

cat <<MSG
# Run these yourself (this script does not call eksctl/aws with mutating verbs):
eksctl create iamserviceaccount \\
  --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" \\
  --namespace external-secrets --name external-secrets \\
  --role-name ch14-eso-secretsmanager \\
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \\
  --approve --override-existing-serviceaccounts

# Narrower than the managed policy above for anything beyond the lab: scope a custom policy to
# secrets named ch14-team-*/* only (resource ARN prefix), not every secret in the account.
MSG
