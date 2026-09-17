#!/usr/bin/env bash
# Cost guardrail: monthly budget scoped to the lab resource group (notifications are configured in
# the portal: Cost Management > Budgets > k8s-ai-lab > Alert conditions, or via ARM/REST).
# NOTE: AKS creates a second "MC_*" node resource group; the budget below is subscription-wide
# filtered to both RGs so node VM costs are included.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AZ_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
BUDGET_USD="${BUDGET_USD:-50}"
NODE_RG="$(az aks show -g "$AZ_RESOURCE_GROUP" -n "$AKS_CLUSTER" --query nodeResourceGroup -o tsv 2>/dev/null || echo "MC_${AZ_RESOURCE_GROUP}_${AKS_CLUSTER}_${AZ_LOCATION:-eastus}")"
START="$(date -u +%Y-%m-01)"
END="$(date -u -v+1y +%Y-%m-01 2>/dev/null || date -u -d '+1 year' +%Y-%m-01)"

az consumption budget create \
  --budget-name k8s-ai-lab \
  --amount "$BUDGET_USD" \
  --category cost \
  --time-grain monthly \
  --start-date "$START" --end-date "$END" \
  --resource-group-filter "$AZ_RESOURCE_GROUP" "$NODE_RG"
# VERIFY: `az consumption` is a legacy command group without notification flags; add email alert
# thresholds (50/90/100%) in the portal, or use `az rest` against Microsoft.Consumption/budgets.
az consumption budget list -o table
