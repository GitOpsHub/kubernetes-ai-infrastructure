#!/usr/bin/env bash
# This script only PRINTS the teardown command — it does not run kubectl/argocd against your
# live cluster, consistent with this course's rule that GitOps-managing chapters never touch a
# real Argo CD themselves. Review, then run it yourself.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat <<MSG
# Delete the root Application (Argo CD's cascade finalizer removes everything it manages too,
# since app-of-apps children inherit no finalizer by default here — check
# 'kubectl get application -n argocd -l app.kubernetes.io/part-of=ai-platform' first if you
# want to delete children individually instead of cascading):
kubectl delete -f ${HERE}/root-app.yaml
kubectl delete -f ${HERE}/../common/argocd-apps/project.yaml
MSG
