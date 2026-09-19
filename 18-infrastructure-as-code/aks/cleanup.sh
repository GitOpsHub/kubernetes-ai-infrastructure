#!/usr/bin/env bash
# Tear down what THIS Terraform module created — only relevant if you went beyond the chapter's
# read-only lab and ran a real 'terraform apply' here. The lab itself (fmt/init -backend=false/
# validate) creates nothing, so there is nothing to clean up and this script will say so.
#
# Deliberately a thin, guarded wrapper around 'terraform destroy' rather than a CLI script:
#   - refuses to run unless CONFIRM=yes (destroy is irreversible);
#   - refuses if the configured state is empty (e.g. after only 'init -backend=false');
#   - still shows Terraform's own destroy plan and prompt — this script never passes -auto-approve.
# Usage:  CONFIRM=yes ./18-infrastructure-as-code/aks/cleanup.sh [extra terraform destroy args, e.g. -var-file=...]
#
# AKS: the node resource group (MC_*) is owned by AKS and removed with the cluster. Azure disks /
# public IPs from later chapters' PVCs and LoadBalancer Services live there too, but run those
# chapters' cleanup.sh first anyway so nothing is left mid-delete when the cluster goes.
#
# The remote-state bucket/storage account (versions.tf backend block) is NOT deleted — it was created
# outside this module; remove it yourself once you no longer need the state history.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${CONFIRM:-}" != "yes" ]; then
  echo "Refusing to run: this destroys the AKS resource group, cluster and node pools created by"
  echo "  $HERE"
  echo "Re-run with CONFIRM=yes if that is what you want. Preview first with:"
  echo "  terraform -chdir=\"$HERE\" plan -destroy"
  exit 1
fi

command -v terraform > /dev/null || { echo "terraform not found on PATH" >&2; exit 1; }

if [ ! -d "$HERE/.terraform" ]; then
  echo "$HERE has not been initialised ('terraform init') — nothing was applied from here. Nothing to do."
  exit 0
fi

# 'state list' prints nothing (or errors with "No state file was found") when nothing was ever applied
# against the backend this directory is initialised with.
if ! resources="$(terraform -chdir="$HERE" state list 2>/dev/null)" || [ -z "$resources" ]; then
  echo "No resources in this module's Terraform state — nothing to destroy."
  echo "(If you applied with a remote backend, run 'terraform -chdir=\"$HERE\" init' against it first.)"
  exit 0
fi

echo "Resources currently in state:"
echo "$resources" | sed 's/^/  /'
echo
terraform -chdir="$HERE" destroy "$@"
