# Repository Conventions

How every chapter in this repo is laid out. Read it once before starting; it makes every chapter feel the same.

## Cloud target: EKS — spot first

Every hands-on resource targets **EKS**. All compute examples use **spot capacity by default** (EC2
Spot), with on-demand shown only as the fallback. Because spot nodes can be reclaimed at any time,
chapters explain what that means for the workload (checkpointing, PodDisruptionBudgets, retries,
graceful shutdown).

| | EKS |
|---|---|
| Spot node label | `eks.amazonaws.com/capacityType: SPOT` (managed node groups) / `karpenter.sh/capacity-type: spot` |
| Spot taint (added automatically?) | No (add yourself) |
| CLI | `eksctl` + `aws` |

> Chapter READMEs are the source of truth for exact labels/flags per resource — verify against the AWS docs linked there.

## Chapter layout

```
NN-chapter-slug/
├── README.md          # theory + lab walkthrough (start here) — every command is inlined, copy-pasteable
├── common/            # cloud-agnostic Kubernetes manifests (kustomize base)
│   └── kustomization.yaml
├── eks/               # EKS: kustomize overlay, Helm values, eksctl/patch YAML referenced by the README
└── cpu-lab/           # (optional) no-GPU variant so you can learn before GPU quota arrives
```

- Apply a chapter's workloads with `kubectl apply -k NN-slug/eks`. The overlay adds node selectors,
  tolerations, storage classes, annotations.
- Helm/eksctl/kubectl operations are inlined directly in each README's Lab section as copy-pasteable
  bash blocks, always with `--version` pinned from [`versions.env`](versions.env) — there are no
  separate `install.sh`/`create-*.sh` script files to open.
- Every chapter's README ends with a Cleanup section — **GPU and spot nodes cost money; tear down when
  done.** (Chapter 18's `eks/cleanup.sh` stays a script: it's a guarded `terraform destroy` wrapper with
  real safety logic, since its `eks/` folder is a Terraform module.)
- A chapter that needs application code (chapter 19) keeps it under `common/src/`: code built into an
  image by a build step, and/or scripts mounted into pods via `configMapGenerator`. It lives inside
  `common/` because kustomize can't reference files outside the kustomization root. Python there is run
  with [uv](https://docs.astral.sh/uv/) (`uv run` / `uv pip`), never pip, with every dependency pinned.

## Each README contains

0. **Before you start** — which earlier chapters' output this one assumes (cluster, node group, CRDs,
   storage) and any optional prerequisites, so you know what to go back and do first
1. **Why this matters** — the problem, in DevOps terms
2. **Learning objectives** and a **~3 hour time plan** (theory / lab / review)
3. **Concepts** with diagrams (Mermaid or ASCII)
4. **Lab** — numbered, independently copy-pasteable EKS steps. Every step says what it does and why
   *before* the command, and gives an **expected output** snippet plus a one-line **"how to tell this
   worked"** *after* it — you should never have to type a command blind, open a script file to see what
   it runs, or guess whether it succeeded.
5. **Spot considerations** for this topic
6. **Troubleshooting** — the failures you will actually hit
7. **Cleanup** and **cost notes**
8. **Checkpoint questions** (answer before moving on) — testing the lab you just did, not generic trivia
9. **Further reading** (official docs) and **versions tested**

## Environment

```bash
cp env.sh.example env.sh   # fill in your AWS account/region
source env.sh && source versions.env
```

Namespaces are per chapter (`ch01-gpu`, `ch06-kueue`, …) unless a component has a conventional namespace
(`gpu-operator`, `kueue-system`, `monitoring`, `kserve`, `karpenter`).

## Validation

Every kustomize overlay and shell script in the repo is checked by
[`scripts/validate-all.sh`](scripts/validate-all.sh) — the same script CI runs on every PR
([`.github/workflows/validate.yml`](.github/workflows/validate.yml)). Run it before you push:

```bash
./scripts/validate-all.sh
```

It renders every overlay (`kubectl kustomize`), schema-checks the core Kubernetes resources in the
result (`kubeconform`, CRDs intentionally skipped — see the script's header comment for why), and syntax-
/lint-checks every shell script. It never touches a live cluster or cloud account.
