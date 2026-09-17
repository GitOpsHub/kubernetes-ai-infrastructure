#!/usr/bin/env bash
# Read-only: prints which tools are present and their versions.
set -euo pipefail
for t in kubectl helm kustomize gcloud gke-gcloud-auth-plugin aws eksctl az k9s jq; do
  if command -v "$t" >/dev/null 2>&1; then printf "%-24s OK   %s\n" "$t" "$(command -v "$t")"
  else printf "%-24s MISSING\n" "$t"; fi
done
