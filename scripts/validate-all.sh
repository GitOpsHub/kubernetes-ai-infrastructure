#!/usr/bin/env bash
# Repo-wide validation used both locally and in CI (.github/workflows/validate.yml).
#
# Checks, in order:
#   1. every kustomize overlay renders (`kubectl kustomize`) -- for chapters not yet migrated
#      off kustomize; every plain-YAML chapter (no kustomization.yaml) is checked directly instead
#   2. every core Kubernetes resource -- from a rendered overlay or a plain manifest file -- is
#      schema-valid (`kubeconform`). CRDs (TrainJob, RayCluster, InferencePool, ...) are
#      intentionally SKIPPED, not failed: kubeconform has no schema for them and validating a
#      fast-moving CRD against a stale cached schema would be worse than not checking it at all.
#      Cross-check those by hand against the pinned version's CRD source when you touch them
#      (see CLAUDE.md).
#   3. every shell script passes `bash -n` (syntax) and, if shellcheck is installed, a lint pass
#   4. the Terraform module (18-infrastructure-as-code/eks) passes `terraform fmt
#      -check` and `terraform validate` (init with -backend=false -- no real backend/credentials)
#
# Usage: ./scripts/validate-all.sh   (run from anywhere; paths are repo-relative)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail=0
K8S_VERSION="${K8S_VERSION:-1.36.0}"   # matches the GKE control-plane version this course was written against

# Only check files git actually tracks -- skips .gitignore'd files like env.sh (real
# credentials/project IDs, meant to be sourced, not linted as a standalone script).
KUSTOMIZATIONS="$(git ls-files -- '*/kustomization.yaml' | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done | sort)"
SCRIPTS="$(git ls-files -- '*.sh' | sort)"

# Plain Kubernetes manifests: any tracked chapter-level YAML file that isn't itself a
# kustomization.yaml, isn't a rendered/gitignored artifact, and isn't a non-manifest config file
# (eksctl ClusterConfig, Helm values, website/docusaurus config, GitHub Actions, etc). We only
# want files that are actual `kind:`-bearing Kubernetes resources meant to be `kubectl apply -f`'d
# directly -- chapters still on kustomize keep their raw resource fragments out of this list
# because kustomize (not kubectl) is what assembles/validates those.
PLAIN_MANIFESTS="$( { git ls-files -- '*.yaml'; git ls-files --others --exclude-standard -- '*.yaml'; } \
  | grep -E '^[0-9]{2}-[^/]+/' \
  | grep -v '/kustomization\.yaml$' \
  | grep -v '/values-.*\.yaml$' \
  | sort -u \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue
      dir="$(dirname "$f")"
      # Skip any file that lives in a directory a kustomization.yaml also lives in --
      # those are overlay/base fragments, not standalone apply-able manifests.
      [ -f "$dir/kustomization.yaml" ] && continue
      # A `kind:` field alone is not enough -- an eksctl ClusterConfig (cluster.yaml,
      # nodegroups.yaml, ...) also has one but lives on apiVersion eksctl.io, not a
      # Kubernetes apiVersion, and kubeconform must not try to validate it.
      grep -q '^kind:' "$f" && ! grep -q '^apiVersion: eksctl\.io' "$f" && echo "$f"
    done | sort)"

echo "== 1/4 kustomize build =="
while IFS= read -r kfile; do
  [ -z "$kfile" ] && continue
  dir="$(dirname "$kfile")"
  if ! kubectl kustomize "$dir" > /dev/null 2>/tmp/kustomize-err; then
    echo "FAIL  $dir"
    sed 's/^/      /' /tmp/kustomize-err
    fail=1
  fi
done <<< "$KUSTOMIZATIONS"
[ "$fail" -eq 0 ] && echo "  all overlays render cleanly"

echo
echo "== 2/4 kubeconform (core K8s resources only; CRDs skipped) =="
if command -v kubeconform > /dev/null; then
  while IFS= read -r kfile; do
    [ -z "$kfile" ] && continue
    dir="$(dirname "$kfile")"
    out=$(kubectl kustomize "$dir" 2>/dev/null | kubeconform -summary -ignore-missing-schemas -kubernetes-version "$K8S_VERSION" 2>&1) || true
    if echo "$out" | grep -q "Invalid: [1-9]\|Errors: [1-9]"; then
      echo "FAIL  $dir"
      echo "$out" | sed 's/^/      /'
      fail=1
    fi
  done <<< "$KUSTOMIZATIONS"
  if [ -n "$PLAIN_MANIFESTS" ]; then
    # Word-splitting $PLAIN_MANIFESTS into multiple file arguments is intentional here.
    # shellcheck disable=SC2086
    out=$(kubeconform -summary -ignore-missing-schemas -kubernetes-version "$K8S_VERSION" $PLAIN_MANIFESTS 2>&1) || true
    if echo "$out" | grep -q "Invalid: [1-9]\|Errors: [1-9]"; then
      echo "FAIL  plain-YAML manifests"
      echo "$out" | sed 's/^/      /'
      fail=1
    fi
  fi
  [ "$fail" -eq 0 ] && echo "  no invalid core resources"
else
  echo "  kubeconform not installed -- skipping (install: https://github.com/yannh/kubeconform)"
fi

echo
echo "== 3/4 shell scripts =="
while IFS= read -r script; do
  [ -z "$script" ] && continue
  if ! bash -n "$script" 2>/tmp/bash-err; then
    echo "FAIL  $script (syntax)"
    sed 's/^/      /' /tmp/bash-err
    fail=1
  fi
  if [ ! -x "$script" ]; then
    echo "FAIL  $script (not executable -- chmod +x)"
    fail=1
  fi
done <<< "$SCRIPTS"
if command -v shellcheck > /dev/null; then
  # style/portability lint -- warnings don't fail the build, only real errors (-S error) do
  while IFS= read -r script; do
    [ -z "$script" ] && continue
    if ! shellcheck -S error "$script" > /tmp/shellcheck-err 2>&1; then
      echo "FAIL  $script (shellcheck)"
      sed 's/^/      /' /tmp/shellcheck-err
      fail=1
    fi
  done <<< "$SCRIPTS"
else
  echo "  shellcheck not installed -- skipping"
fi
[ "$fail" -eq 0 ] && echo "  all scripts OK"

echo
echo "== 4/4 terraform (18-infrastructure-as-code) =="
if command -v terraform > /dev/null; then
  for tfdir in 18-infrastructure-as-code/eks; do
    [ -d "$tfdir" ] || continue
    if ! terraform -chdir="$tfdir" fmt -check -recursive > /tmp/tf-fmt-err 2>&1; then
      echo "FAIL  $tfdir (terraform fmt -- run 'terraform fmt' to fix)"
      sed 's/^/      /' /tmp/tf-fmt-err
      fail=1
    fi
    if ! terraform -chdir="$tfdir" init -backend=false -input=false > /tmp/tf-init-err 2>&1; then
      echo "FAIL  $tfdir (terraform init)"
      sed 's/^/      /' /tmp/tf-init-err
      fail=1
      continue
    fi
    if ! terraform -chdir="$tfdir" validate > /tmp/tf-validate-err 2>&1; then
      echo "FAIL  $tfdir (terraform validate)"
      sed 's/^/      /' /tmp/tf-validate-err
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] && echo "  all modules OK"
else
  echo "  terraform not installed -- skipping (install: https://developer.hashicorp.com/terraform/install)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS: repo validates clean"
else
  echo "FAIL: see above"
  exit 1
fi
