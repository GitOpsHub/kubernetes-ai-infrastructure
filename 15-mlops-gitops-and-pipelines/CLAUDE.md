# 15-mlops-gitops-and-pipelines/CLAUDE.md

This chapter builds an Argo CD app-of-apps intended to layer onto the user's **existing, live** Argo CD
install (chart `argo-cd`, namespace `argocd`). Its manifests use placeholder values (`YOUR_ORG`,
`YOUR_PROJECT`, `YOUR_ACCOUNT_ID`) that must be filled in per-fork/per-account before applying — do not
assume a real repo URL or cloud project ID when editing it.
