# Repository Conventions

Every chapter in this repo follows the same layout and README structure. Read this once before
starting -- it makes every chapter feel familiar and tells you exactly where to look for anything.

---

## Cloud target: EKS -- spot first

Every hands-on resource targets **EKS**. All compute examples use **spot capacity by default** (EC2
Spot), with on-demand shown only as the fallback. Because spot nodes can be reclaimed at any time,
chapters explain what that means for the workload (checkpointing, PodDisruptionBudgets, retries,
graceful shutdown).

| | EKS |
|---|---|
| Spot node label | `eks.amazonaws.com/capacityType: SPOT` (managed node groups) / `karpenter.sh/capacity-type: spot` |
| Spot taint (added automatically?) | No -- add yourself if you want workloads to require an explicit toleration |
| CLI | `eksctl` + `aws` |

> Chapter READMEs are the source of truth for exact labels/flags per resource -- verify against the AWS docs linked there.

---

## Tools you need installed

These are needed before running any chapter lab. Chapter 00 Step 1 walks through installing all of
them on macOS and Linux:

| Tool | Used for | Required? |
|---|---|---|
| `kubectl` | Applying and inspecting Kubernetes resources | **Yes** |
| `helm` | Installing operators and stacks via Helm charts | **Yes** |
| `kustomize` | Building chapter overlays (`kubectl apply -k`) | **Yes** |
| `aws` CLI v2 | AWS account, IAM, quota, budget commands | **Yes** |
| `eksctl` | Creating and managing EKS clusters and node groups | **Yes** |
| `jq` / `yq` | Parsing JSON/YAML output in shell snippets | **Yes** |
| `k9s` | Interactive terminal UI for cluster browsing | Optional |
| `kubeconform` | Schema-validates rendered Kubernetes manifests in CI | Optional (CI uses it) |
| `shellcheck` | Lints shell scripts in CI | Optional (CI uses it) |
| `terraform` | Required only for chapter 18 (Infrastructure as Code) | Ch18 only |

---

## Chapter layout

```
NN-chapter-slug/
├── README.md          # theory + lab walkthrough (start here) -- every command is inlined, copy-pasteable
├── common/            # cloud-agnostic Kubernetes manifests (kustomize base)
│   └── kustomization.yaml
├── eks/               # EKS: kustomize overlay, Helm values, eksctl/patch YAML referenced by the README
└── cpu-lab/           # (optional) no-GPU variant so you can learn before GPU quota arrives
```

- Apply a chapter's workloads with `kubectl apply -k NN-slug/eks`. The overlay adds node selectors,
  tolerations, storage classes, annotations.
- Helm/eksctl/kubectl operations are inlined directly in each README's Lab section as copy-pasteable
  bash blocks, always with `--version` pinned from [`versions.env`](versions.env) -- there are no
  separate `install.sh`/`create-*.sh` script files to open.
- Every chapter's README ends with a Cleanup section -- **GPU and spot nodes cost money; tear down when
  done.** (Chapter 18's `eks/cleanup.sh` stays a script: it's a guarded `terraform destroy` wrapper with
  real safety logic, since its `eks/` folder is a Terraform module.)
- A chapter that needs application code (chapter 19) keeps it under `common/src/`: code built into an
  image by a build step, and/or scripts mounted into pods via `configMapGenerator`. It lives inside
  `common/` because kustomize can't reference files outside the kustomization root. Python there is run
  with [uv](https://docs.astral.sh/uv/) (`uv run` / `uv pip`), never pip, with every dependency pinned.

---

## Each README contains

The sections below are the required structure for every chapter README. Section 0 ("Before you
start") must always be present so readers know exactly what earlier chapter output they need before
running any command.

0. **Before you start** -- which earlier chapters' output this one assumes (cluster, node group, CRDs,
   storage) and any optional prerequisites, so you know what to go back and do first
1. **Why this matters** -- the problem, in DevOps terms
2. **Learning objectives** and a **~3 hour time plan** (theory / lab / review)
3. **Concepts** with diagrams (Mermaid or ASCII)
4. **Lab** -- numbered, independently copy-pasteable EKS steps. Every step says what it does and why
   *before* the command, and gives an **expected output** snippet plus a one-line **"how to tell this
   worked"** *after* it -- you should never have to type a command blind, open a script file to see what
   it runs, or guess whether it succeeded.
5. **Spot considerations** for this topic
6. **Troubleshooting** -- the failures you will actually hit
7. **Cleanup** and **cost notes**
8. **Checkpoint questions** (answer before moving on) -- testing the lab you just did, not generic trivia
9. **Further reading** (official docs) and **versions tested**

---

## Environment

```bash
cp env.sh.example env.sh   # fill in your AWS account/region/budget email
source env.sh && source versions.env
```

Namespaces are per chapter (`ch01-gpu`, `ch06-kueue`, ...) unless a component has a conventional
namespace (`gpu-operator`, `kueue-system`, `monitoring`, `kserve`, `karpenter`, `argocd`).

---

## Chapter 15 note: placeholder values

Chapter 15 (`15-mlops-gitops-and-pipelines`) builds an Argo CD app-of-apps. Its manifests use
placeholder values (`YOUR_ORG`, `YOUR_PROJECT`, `YOUR_ACCOUNT_ID`) that must be replaced with your
own values before applying -- do not assume a real repo URL or cloud account ID. See that chapter's
README for the full list of values to substitute.

---

## Validation

Every kustomize overlay and shell script in the repo is checked by
[`scripts/validate-all.sh`](scripts/validate-all.sh) -- the same script CI runs on every PR
([`.github/workflows/validate.yml`](.github/workflows/validate.yml)). Run it before you push:

```bash
./scripts/validate-all.sh
```

The script runs four checks:

1. **kustomize build** -- every overlay renders without error (`kubectl kustomize`)
2. **kubeconform** -- schema-validates core Kubernetes resources in the rendered output; CRDs are
   intentionally skipped (see script header for why). Install: `brew install kubeconform` or
   https://github.com/yannh/kubeconform (optional but recommended).
3. **Shell scripts** -- `bash -n` syntax check + `shellcheck` lint (shellcheck optional:
   `brew install shellcheck`). Every `.sh` file tracked by git must also be executable (`chmod +x`).
4. **Terraform** -- `terraform fmt -check` and `terraform validate` for chapter 18's module
   (optional if you haven't touched chapter 18; install: https://developer.hashicorp.com/terraform/install).

It renders every overlay (`kubectl kustomize`) and never touches a live cluster or cloud account.
