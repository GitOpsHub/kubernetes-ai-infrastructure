#!/usr/bin/env bash
# Read-only: EC2 vCPU quotas that gate this course. New accounts often have 0 for G/VT.
#   L-3819A6DF  All G and VT Spot Instance Requests        (spot g6/g4dn)  <- the one you need
#   L-DB2E81BA  Running On-Demand G and VT instances       (on-demand fallback)
#   L-34B43A08  All Standard (A,C,D,H,I,M,R,T,Z) Spot Instance Requests (spot CPU pool)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}"
for q in L-3819A6DF L-DB2E81BA L-34B43A08; do
  aws service-quotas get-service-quota --region "$AWS_REGION" --service-code ec2 --quota-code "$q" \
    --query 'Quota.[QuotaCode,QuotaName,Value]' --output text
done
cat <<MSG

Quotas are in vCPUs: one g6.xlarge / g4dn.xlarge = 4 vCPUs. Request at least 8 for spot:
  aws service-quotas request-service-quota-increase --region ${AWS_REGION} \\
     --service-code ec2 --quota-code L-3819A6DF --desired-value 8
Track it:
  aws service-quotas list-requested-service-quota-change-history-by-quota --region ${AWS_REGION} \\
     --service-code ec2 --quota-code L-3819A6DF
MSG
