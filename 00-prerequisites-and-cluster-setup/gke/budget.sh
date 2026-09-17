#!/usr/bin/env bash
# Cost guardrail: monthly budget on the project with 50% / 90% actual and 100% forecast alerts.
# Budgets ALERT, they do not stop spend. Pair with cleanup.sh and scale-to-zero GPU pools.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${PROJECT_ID:?}"
BUDGET_USD="${BUDGET_USD:-50}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' | sed 's#billingAccounts/##')}"
: "${BILLING_ACCOUNT:?could not detect billing account}"

gcloud services enable billingbudgets.googleapis.com --project "$PROJECT_ID"
gcloud billing budgets create \
  --billing-account="$BILLING_ACCOUNT" \
  --display-name="k8s-ai-lab-${PROJECT_ID}" \
  --budget-amount="${BUDGET_USD}USD" \
  --filter-projects="projects/${PROJECT_ID}" \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0,basis=forecasted-spend
gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --format="table(displayName,amount.specifiedAmount.units)"
