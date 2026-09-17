# Repository Conventions

How every chapter in this repo is laid out. Read it once before starting; it makes every chapter feel the same.

## Cloud targets: GKE, EKS, AKS — spot first

Every hands-on resource has a variant for **GKE**, **EKS** and **AKS**. All compute examples use
**spot / preemptible capacity by default** (GKE Spot VMs, EC2 Spot, Azure Spot VMs), with on-demand
shown only as the fallback. Because spot nodes can be reclaimed at any time, chapters explain what that
means for the workload (checkpointing, PodDisruptionBudgets, retries, graceful shutdown).

| | GKE | EKS | AKS |
|---|---|---|---|
| Spot node label | `cloud.google.com/gke-spot: "true"` | `eks.amazonaws.com/capacityType: SPOT` (managed node groups) / `karpenter.sh/capacity-type: spot` | `kubernetes.azure.com/scalesetpriority: spot` |
| Spot taint (added automatically?) | No by default (add `cloud.google.com/gke-spot=true:NoSchedule` yourself if wanted) | No (add yourself) | **Yes**: `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` |
| CLI | `gcloud` | `eksctl` + `aws` | `az` |

> Chapter READMEs are the source of truth for exact labels/flags per resource — verify against the cloud docs linked there.

## Chapter layout

```
NN-chapter-slug/
├── README.md          # theory + lab walkthrough (start here)
├── common/            # cloud-agnostic Kubernetes manifests (kustomize base)
│   └── kustomization.yaml
├── gke/               # GKE: cluster/nodepool scripts, kustomize overlay, Helm values
│   ├── kustomization.yaml
│   └── *.sh / values-*.yaml
├── eks/               # EKS: eksctl configs, kustomize overlay, Helm values
├── aks/               # AKS: az scripts, kustomize overlay, Helm values
└── cpu-lab/           # (optional) no-GPU variant so you can learn before GPU quota arrives
```

- Apply a chapter's workloads with `kubectl apply -k NN-slug/gke` (or `eks` / `aks`). The overlay adds
  cloud-specific node selectors, tolerations, storage classes, annotations.
- Helm installs are scripted in `install.sh` per cloud folder, always with `--version` pinned from
  [`versions.env`](versions.env).
- Every chapter ships a `cleanup.sh` (per cloud) — **GPU and spot nodes cost money; tear down when done.**

## Each README contains

1. **Why this matters** — the problem, in DevOps terms
2. **Learning objectives** and a **~3 hour time plan** (theory / lab / review)
3. **Concepts** with diagrams (Mermaid or ASCII)
4. **Lab** — numbered steps with GKE / EKS / AKS tabs-as-subsections, expected output, verification
5. **Spot considerations** for this topic
6. **Troubleshooting** — the failures you will actually hit
7. **Cleanup** and **cost notes**
8. **Checkpoint questions** (answer before moving on)
9. **Further reading** (official docs) and **versions tested**

## Environment

```bash
cp env.sh.example env.sh   # fill in project/account/subscription values
source env.sh && source versions.env
```

Namespaces are per chapter (`ch01-gpu`, `ch06-kueue`, …) unless a component has a conventional namespace
(`gpu-operator`, `kueue-system`, `monitoring`, `kserve`, `karpenter`).
