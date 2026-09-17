#!/usr/bin/env bash
# Install the CLI toolchain used throughout the course on macOS (Homebrew).
# Linux users: see README "1. Tools" for the official install links.
set -euo pipefail

command -v brew >/dev/null || { echo "Homebrew not found: https://brew.sh"; exit 1; }

brew install kubernetes-cli helm kustomize k9s jq yq \
             awscli eksctl azure-cli
brew install --cask gcloud-cli

# GKE needs the auth plugin for kubectl (kubectl talks to GKE through it)
gcloud components install gke-gcloud-auth-plugin --quiet || \
  echo "If gcloud components are managed by Homebrew, the plugin may already be bundled."

echo "--- versions ---"
kubectl version --client
helm version --short
kustomize version
gcloud version | head -1
aws --version
eksctl version
az version --query '"azure-cli"' -o tsv
