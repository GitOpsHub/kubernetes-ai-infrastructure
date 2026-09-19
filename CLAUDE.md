# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A hands-on course teaching Kubernetes for AI workloads (GPU scheduling, training, LLM serving,
autoscaling, cost) to a DevOps audience. It is not an application — there is no build/lint/test suite.
The "product" is a sequence of 20 numbered chapters (`00-prerequisites-and-cluster-setup` through
`19-llm-pipelines-huggingface-langchain`), each a self-contained lab with Kubernetes manifests, Helm values,
and shell scripts for **GKE, EKS, and AKS**. Chapter 18 is the one exception — Terraform instead of
kustomize, see its README for why. Chapter 19 is **AWS/EKS-first** (EKS is the fully-worked cloud; GKE/AKS
overlays are at parity for the Kubernetes objects) and is the only chapter that carries Python sources:
`common/src/` holds the trainer code (built into an image by a per-cloud build script) and PEP 723
`uv run` scripts (mounted into pods via kustomize `configMapGenerator`, which is why they live inside the
chapter's `common/` kustomization root). Read [README.md](README.md) for the course map and
[CONVENTIONS.md](CONVENTIONS.md) for the full chapter layout contract before adding or editing a chapter.

## Environment setup

```bash
cp env.sh.example env.sh      # fill in GCP project / AWS account / Azure subscription — env.sh is gitignored
source env.sh && source versions.env
```

`versions.env` pins every component version (Helm chart versions, image tags, CLI-relevant releases)
used across all chapters. Chapter scripts reference these as `${KUEUE_VERSION}`, `${VLLM_VERSION}`, etc.
When bumping a pinned version, update `versions.env` and the affected chapter's "Versions tested" table
together — don't let them drift.

## Validating changes (no test suite — use these instead)

```bash
# Validate a chapter overlay renders without error
kubectl kustomize <chapter>/<cloud>       # cloud = common | gke | eks | aks | cpu-lab

# Validate every overlay in the repo
for d in $(find [0-9][0-9]-* -name kustomization.yaml -exec dirname {} \; | sort -u); do
  kubectl kustomize "$d" > /dev/null || echo "FAIL $d"
done

# Validate a Helm values file against the real chart (don't hand-verify field names from memory)
helm show values <chart>@<pinned-version>
helm template <chart>@<pinned-version> -f <chapter>/<cloud>/values-*.yaml

# Shell scripts
bash -n <script>.sh && chmod +x <script>.sh
```

**No commands here touch a live cluster or cloud account** — `kubectl kustomize`, `helm template`, and
`bash -n` are all local/dry-run. Never run `kubectl apply`, `helm install`, or cloud CLI (`gcloud`/`aws`/
`eksctl`/`az`) mutating commands against a real cluster/account without the user's explicit go-ahead —
GPU node pools and spot capacity cost real money the moment they're created.

## Repo-wide invariants (see CONVENTIONS.md for full detail)

- **Every hands-on resource has GKE, EKS, and AKS variants**: a cloud-agnostic `common/` kustomize base,
  overlaid by `gke/`, `eks/`, `aks/` (node selectors, tolerations, storage classes, per-cloud install
  scripts). Most chapters also ship a `cpu-lab/` variant so the mechanics can be learned without GPU
  quota.
- **Spot capacity is the default**, on-demand is the documented fallback. Each cloud has a different spot
  node label and taint behavior — AKS auto-taints spot node pools (`kubernetes.azure.com/scalesetpriority=spot:NoSchedule`),
  GKE/EKS do not unless you add the taint yourself. Get this wrong and pods silently stay Pending.
- **Chapter layout is fixed**: `README.md`, `common/`, `gke/`, `eks/`, `aks/`, optional `cpu-lab/`, each
  cloud folder has its own `install.sh`/`create-*.sh` and `cleanup.sh`. New chapters must follow this
  shape exactly — see CONVENTIONS.md's directory tree and the required README sections (Why it matters,
  objectives + time plan, concepts with a diagram, per-cloud lab steps, spot considerations,
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

## Chapter 15's GitOps note

Chapter 15 builds an Argo CD app-of-apps intended to layer onto the user's **existing, live** Argo CD
install (chart `argo-cd`, namespace `argocd`). Its manifests use placeholder values (`YOUR_ORG`,
`YOUR_PROJECT`, `YOUR_ACCOUNT_ID`) that must be filled in per-fork/per-account before applying — do not
assume a real repo URL or cloud project ID when editing it.
