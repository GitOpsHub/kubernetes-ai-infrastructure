#!/usr/bin/env bash
# Read-only: vCPU quotas for this course. Spot VMs draw from the regional Spot ("low-priority")
# vCPU quota, separate from per-family on-demand quotas. Standard_NC4as_T4_v3 = 4 vCPUs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_LOCATION:?}"
az vm list-usage --location "$AZ_LOCATION" -o table \
  | grep -iE 'Name|Spot|Low-priority|NCASv3_T4|NCADS_A10|DSv5|Total Regional' || true
# Is the GPU size offered (and not restricted for your subscription) in this region?
az vm list-skus --location "$AZ_LOCATION" --size Standard_NC4as_T4_v3 \
  --query '[].{name:name, zones:locationInfo[0].zones, restrictions:restrictions[].reasonCode}' -o table
cat <<MSG

Request increases in the portal: Subscriptions > Usage + quotas, filter region ${AZ_LOCATION}:
  - "Total Regional Spot vCPUs" (may display as Low-priority vCPUs)  -> >= 8   # used by spot pools
  - "Standard NCASv3_T4 Family vCPUs"                                -> >= 4   # on-demand fallback only
Free-trial / some sponsorship subscriptions cannot get GPU quota: upgrade to pay-as-you-go first.
MSG
