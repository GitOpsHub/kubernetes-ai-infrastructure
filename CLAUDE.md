# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A hands-on course teaching Kubernetes for AI workloads (GPU scheduling, training, LLM serving,
autoscaling, cost) to a DevOps audience. It is not an application in the product sense — there's no app
to build or ship — but the repo does carry a real CI/validation layer (see below), so "no test suite"
no longer applies. The "product" is a sequence of 20 numbered chapters (`00-prerequisites-and-cluster-setup`
through `19-llm-pipelines-huggingface-langchain`), each a self-contained lab with Kubernetes manifests,
Helm values, and an **EKS**-only overlay. Every operational step (cluster/nodegroup creation, Helm
installs, scale/cleanup) is inlined as copy-pasteable bash in the chapter's README — there are no
per-chapter `create-*.sh`/`install-*.sh` script files to open. Chapter 18 is the one exception — its
`eks/` folder is a Terraform module instead of a kustomize overlay, see its README for why (it also
keeps a real `cleanup.sh`, a guarded `terraform destroy` wrapper — that one stays a script because the
safety guard is the point). Chapter 19 is the only chapter that carries Python sources: `common/src/`
holds the trainer code (built into an image) and PEP 723 `uv run` scripts (mounted into pods via
kustomize `configMapGenerator`, which is why they live inside the chapter's `common/` kustomization
root). Read [README.md](README.md) for the course map and [CONVENTIONS.md](CONVENTIONS.md) for the
full chapter layout contract before adding or editing a chapter.

The repo also publishes a Docusaurus docs site from `website/` (see "Docs website" below) and a
research/notes file, [AI_INFRASTRUCTURE_RESEARCH_AND_ARTICLES.md](AI_INFRASTRUCTURE_RESEARCH_AND_ARTICLES.md),
that isn't part of the course itself.

## Environment setup

```bash
cp env.sh.example env.sh      # fill in your AWS account/region — env.sh is gitignored
source env.sh && source versions.env
```

`versions.env` pins every component version (Helm chart versions, image tags, CLI-relevant releases)
used across all chapters. Chapter READMEs reference these as `${KUEUE_VERSION}`, `${VLLM_VERSION}`, etc.
When bumping a pinned version, update `versions.env` and the affected chapter's "Versions tested" table
together — don't let them drift.

## Validating changes

```bash
# Repo-wide check — same thing CI runs on every PR touching yaml/yml/sh
# (kustomize build, kubeconform on core resources, shellcheck/bash -n, terraform fmt+validate for ch18)
./scripts/validate-all.sh

# Validate a single chapter overlay renders without error
kubectl kustomize <chapter>/<cloud>       # cloud = common | eks | cpu-lab

# Validate a Helm values file against the real chart (don't hand-verify field names from memory)
helm show values <chart>@<pinned-version>
helm template <chart>@<pinned-version> -f <chapter>/eks/values-*.yaml
```

[scripts/validate-all.sh](scripts/validate-all.sh) is what [.github/workflows/validate.yml](.github/workflows/validate.yml)
runs on every PR that touches `**/*.yaml`, `**/*.yml`, or `**/*.sh`, plus every push to `main`. It
intentionally skips CRD schema validation (Kueue's `TrainJob`, `RayCluster`, `InferencePool`, …) —
kubeconform has no schema for them, so cross-check those by hand against the pinned version's CRD
source instead of trusting a clean run. A separate workflow, [.github/workflows/deploy-docs.yml](.github/workflows/deploy-docs.yml),
builds and publishes the `website/` docs site to GitHub Pages on every push to `main` that touches
any `**.md` or `website/**` — it is unrelated to the kustomize/Terraform validation above.

**No commands here touch a live cluster or cloud account** — `kubectl kustomize`, `helm template`, and
`scripts/validate-all.sh` are all local/dry-run (it runs `terraform init -backend=false`, no real
backend/credentials). Never run `kubectl apply`, `helm install`, or `aws`/`eksctl` mutating commands
against a real cluster/account without the user's explicit go-ahead — GPU node groups and spot capacity
cost real money the moment they're created.

## Repo-wide invariants (see CONVENTIONS.md for full detail)

- **Every hands-on resource targets EKS**: a cloud-agnostic `common/` kustomize base, overlaid by `eks/`
  (node selectors, tolerations, storage classes). Most chapters also ship a `cpu-lab/` variant so the
  mechanics can be learned without GPU quota.
- **Spot capacity is the default**, on-demand is the documented fallback. EKS does not auto-taint spot
  node groups — add the taint yourself if you want workloads to require an explicit toleration. Get this
  wrong and pods silently stay Pending, or land on spot nodes unintentionally.
- **Chapter layout is fixed**: `README.md`, `common/`, `eks/`, optional `cpu-lab/`. The README's Lab
  section inlines every command (no separate `install.sh`/`create-*.sh` files). New chapters must follow
  this shape exactly — see CONVENTIONS.md's directory tree and the required README sections (Why it
  matters, objectives + time plan, concepts with a diagram, lab steps, spot considerations,
  troubleshooting, cleanup/cost notes, checkpoint questions, further reading + versions tested).
- **Kustomize file references must stay inside the kustomization root.** `configMapGenerator`/`secretGenerator`
  `files:` cannot point outside the directory containing `kustomization.yaml` (kustomize's security
  policy rejects it) — copy the file in rather than reaching up with `../../`.
- **Accuracy over recall for API versions/flags.** Several pinned components are on APIs newer or more
  volatile than typical training data (Kueue `kueue.x-k8s.io/v1beta2`, Kubeflow Trainer v2 `TrainJob`/
  `ClusterTrainingRuntime`, KServe's alpha `LLMInferenceService`, Gateway API Inference Extension
  `InferencePool`, DRA `resource.k8s.io/v1`, Karpenter v1 `NodePool`/`EC2NodeClass`). Verify apiVersions,
  CRD fields, Helm values, and CLI flags against the pinned tag's actual source/docs before writing them;
  mark anything you couldn't verify with an inline `# VERIFY:` comment rather than guessing.
- Namespaces are per chapter (`ch06-kueue`, `ch07-training`, …) unless a component has a conventional
  namespace (`gpu-operator`, `kueue-system`, `monitoring`, `kserve`, `karpenter`, `argocd`).

## Docs website (`website/`)

See [website/CLAUDE.md](website/CLAUDE.md) for the Docusaurus sync/build workflow.

## Chapter 15's GitOps note

See [15-mlops-gitops-and-pipelines/CLAUDE.md](15-mlops-gitops-and-pipelines/CLAUDE.md) for the Argo CD app-of-apps caveat.
