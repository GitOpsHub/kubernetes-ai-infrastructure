# 03 · GPU Sharing and Dynamic Resource Allocation

> Time-slicing, MPS and MIG, each cloud's native flavor of them, and Dynamic Resource
> Allocation (`resource.k8s.io/v1`, GA in Kubernetes 1.35) as the newer, more expressive way
> to hand out GPUs.

## Before you start

Needs from [`01-gpu-nodes-and-scheduling`](../01-gpu-nodes-and-scheduling) or
[`02-nvidia-gpu-operator`](../02-nvidia-gpu-operator): a device plugin (either chapter's) already
running on the node pools you point the time-slicing/MPS configs at — this chapter reconfigures the
plugin, it doesn't install one fresh. DRA (Step 3) is the exception: it installs its own driver on a
dedicated node pool and needs no prior device plugin. GPU quota from chapter 00 applies; MIG (Step 4)
additionally needs A100/H100/H200 quota, which is rarer and slower to get approved — request it early
if you plan to do the hands-on MIG lab.

## 1. Why this matters

Chapter 01 gave every pod its own whole GPU (`nvidia.com/gpu: 1`). That's simple and safe, but
most inference and dev workloads use a fraction of a GPU's compute or memory, so a whole-GPU-per-pod
policy leaves expensive hardware idle. This chapter is about **safely putting more than one
workload on one physical GPU**, and about DRA, the newer scheduling API built to express things
the device-plugin model (extended resources) structurally cannot: "any GPU with ≥20Gi memory",
richer per-claim config, and claims shared by name across pods.

- **Time-slicing** is oversubscription with no isolation: N pods share one GPU's compute via
  fast context switching. No memory limit per pod — one pod can OOM the others.
- **MPS** (Multi-Process Service) shares one GPU through a single CUDA context with configurable
  compute/memory quotas per client — better isolation, still one fault domain (an MPS daemon
  crash takes down every client).
- **MIG** (Multi-Instance GPU, A100/H100/H200-class only) physically partitions the GPU into
  independent instances with their own SM, memory and fault isolation — the strongest isolation,
  but fixed at node-creation time and unavailable on cheap GPUs (L4, T4).
- **DRA** doesn't compete with the three above — it's a different scheduling API. The NVIDIA DRA
  driver can *express* time-slicing and MPS as claim config, plus things the extended-resource
  model can't: CEL attribute selectors, and one `ResourceClaim` referenced by name from several
  pods.

```mermaid
flowchart TB
  subgraph Device plugin model - chapters 01,02
    EXT["extended resource:<br/>nvidia.com/gpu: N (integer)"] --> SCHED1[Scheduler:<br/>bin-packs by count]
  end
  subgraph This chapter
    TS[Time-slicing] -->|device-plugin config| DP[NVIDIA device plugin]
    MPS[MPS] -->|device-plugin config or cloud-native| DP
    MIG[MIG] -->|hardware partition| DP
    DP --> EXT
    DRA["DRA: ResourceClaim /<br/>ResourceClaimTemplate /<br/>DeviceClass"] --> SCHED2["Scheduler:<br/>structured, CEL selectors,<br/>opaque per-vendor config"]
  end
```

## 2. Learning objectives and time plan (~3 h)

By the end you can:

1. Explain the isolation/perf trade-offs of time-slicing vs MPS vs MIG and pick one for a workload.
2. Configure GPU sharing the cloud-native way (GKE node pool flags, AKS `--gpu-instance-profile`)
   and the portable way (NVIDIA device plugin `sharing:` config, works the same on GKE/EKS/AKS).
3. Read and write DRA `DeviceClass`, `ResourceClaim`, `ResourceClaimTemplate`, and a CEL device
   selector.
4. Explain why a DRA driver and a device plugin must never manage the same node.
5. Run the same DRA claim mechanics on a free local kind cluster with a simulated GPU driver.

| Time | Activity |
|---|---|
| 0:00–0:35 | Read section 3 (concepts). Skim `common/device-plugin-config/configmap.yaml` and `common/dra/*.yaml` |
| 0:35–1:00 | `cpu-lab/`: DRA claim mechanics on kind, no GPU quota needed |
| 1:00–1:20 | Time-slicing lab on your cloud |
| 1:20–1:40 | MPS lab |
| 1:40–2:15 | DRA lab (single claim, shared claim, CEL selector, opaque sharing config) |
| 2:15–2:45 | MIG (read-through if you don't have A100/H100 quota; hands-on if you do) |
| 2:45–3:00 | Checkpoint questions, cleanup |

## 3. Concepts

### 3.1 Time-slicing vs MPS vs MIG vs DRA

| | Isolation | Memory limit per client | GPUs it works on | Configured via |
|---|---|---|---|---|
| Time-slicing | None (context-switch only) | No | Any | Device plugin `sharing.timeSlicing` config, or GKE/AKS native flag |
| MPS | Process-level, shared fault domain | Yes (per-client quota) | Any (full GPU, not MIG) | Device plugin `sharing.mps` config (or GKE native `gpu-sharing-strategy=mps`) |
| MIG | Hardware (own SM + memory) | Yes (fixed by profile) | A100 / H100 / H200 only | Node-pool-time partition (GKE `gpu-partition-size`, AKS `--gpu-instance-profile`), immutable after creation |
| DRA | Depends on driver's claim config (can express time-slicing/MPS/MIG) | Depends on config | Any, driver-defined | `ResourceClaim`/`ResourceClaimTemplate` + `DeviceClass`, GA API |

### 3.2 Per-cloud native sharing

| | GKE | EKS | AKS |
|---|---|---|---|
| Time-slicing | `--accelerator=...,gpu-sharing-strategy=time-sharing,max-shared-clients-per-gpu=N` on node pool create | No native flag — NVIDIA device plugin `sharing.timeSlicing` config (GPU Operator, chapter 02) | No native flag — same device plugin config as EKS |
| MPS | `--accelerator=...,gpu-sharing-strategy=mps,...` + pods need `hostIPC: true` | Device plugin `sharing.mps` config | Device plugin `sharing.mps` config |
| MIG | `--accelerator=...,gpu-partition-size=1g.5gb,...` on an A100 node pool | MIG Manager (GPU Operator) partitions after node join, label `nvidia.com/mig.config=all-1g.5gb` | `--gpu-instance-profile MIG1g` on node pool create (**immutable**; needs a device plugin installed separately with `migStrategy=single\|mixed`) |
| Resource name (single strategy) | `nvidia.com/gpu` | `nvidia.com/gpu` | `nvidia.com/gpu` |
| Resource name (mixed strategy) | `nvidia.com/mig-<profile>` | `nvidia.com/mig-<profile>` | `nvidia.com/mig-<profile>` |

GKE bakes sharing into the node pool (`gcloud container node-pools create --accelerator=...`);
EKS and AKS have no such flag, so both lean on the same portable mechanism: the NVIDIA device
plugin's `sharing:` block, delivered as a `nvidia.com/device-plugin.config` ConfigMap key and
selected per node with a label (`common/device-plugin-config/configmap.yaml`). This is also why
the EKS and AKS overlays in this chapter look nearly identical to each other and different from GKE.

### 3.3 DRA in one paragraph

DRA replaces "count of an opaque integer resource" with a **claim**: a pod (or several pods)
references a `ResourceClaim` (or gets one generated per-pod from a `ResourceClaimTemplate`), the
claim's `spec.devices.requests` says what it needs (`deviceClassName`, optionally a CEL
`selectors` expression over device attributes/capacity published in `ResourceSlice` objects by
the driver), and the scheduler allocates matching devices at bind time. A `DeviceClass`
(`gpu.nvidia.com` here, `gpu.example.com` in the CPU lab) is a cluster-scoped, admin-defined
"kind of device" claims can request. Config attached to a claim (`config[].opaque`) is passed
through to the driver verbatim — this is how the NVIDIA DRA driver implements time-slicing/MPS
as claim-time config instead of node-time config. See `common/dra/*.yaml` for four patterns:
exclusive claim, claim shared by name across pods, CEL attribute selector, and opaque
time-slicing config across two containers in one pod.

**A DRA driver and the device plugin must never run on the same node** — both would try to
account for and hand out the same physical GPU, and pods could get double-allocated or the
scheduler's view could silently desync from reality. Every cloud's manifests here put DRA on
its own node pool/group (`nvidia.com/gpu.deploy.device-plugin: "false"` on EKS, GKE's
`gke-no-default-nvidia-gpu-device-plugin=true` node label, a dedicated `gpudra` pool with
`--gpu-driver none` and `gpu-mode=dra` label on AKS).

## 4. Lab

```bash
cp env.sh.example env.sh && source env.sh && source versions.env   # if not already
```

Prerequisite: chapter 01 (device plugin) or chapter 02 (GPU Operator) already running on the
node pools you point sharing configs at — this chapter reconfigures the plugin, it doesn't
install it fresh, except for DRA which installs its own separate driver.

### Step 0 (no GPU quota needed): DRA mechanics on kind

```bash
./03-gpu-sharing-and-dra/cpu-lab/create-kind-cluster.sh
./03-gpu-sharing-and-dra/cpu-lab/install-example-driver.sh
kubectl apply -k 03-gpu-sharing-and-dra/cpu-lab
kubectl get resourceclaims -n ch03-dra-cpu-lab
kubectl get pod -n ch03-dra-cpu-lab dra-cpu-single -o jsonpath='{.status.phase}{"\n"}'
kubectl exec -n ch03-dra-cpu-lab dra-cpu-single -- bash -c 'export | grep -i gpu'
```
Expected: two `Running` pods each holding their own simulated GPU claim, and
`dra-cpu-sharing`'s three containers holding claims from the same `ResourceClaimTemplate`
using two different opaque sharing strategies (`TimeSlicing`, `SpacePartitioning`) — the same
claim/template/opaque-config shape as the real NVIDIA driver, verified without any cloud account.

**What doesn't carry over:** no real CUDA context, no memory isolation, no performance signal —
only the API objects, scheduling flow, and claim/config mechanics transfer.

### Step 1: Time-slicing

<details><summary>GKE</summary>

```bash
./03-gpu-sharing-and-dra/gke/create-nodepool-timesharing.sh   # l4-timeshare-spot, 4 clients/GPU
kubectl apply -k 03-gpu-sharing-and-dra/gke/timeslicing
kubectl -n ch03-gpu-sharing get pods -o wide
kubectl -n ch03-gpu-sharing exec deploy/timeslice-demo -- nvidia-smi -L
```
</details>

<details><summary>EKS</summary>

```bash
./03-gpu-sharing-and-dra/eks/create-nodegroups.sh gpu-share-spot
./03-gpu-sharing-and-dra/eks/install-sharing-config.sh        # points GPU Operator at time-sliced-4
kubectl apply -k 03-gpu-sharing-and-dra/eks/timeslicing
```
</details>

<details><summary>AKS</summary>

```bash
./03-gpu-sharing-and-dra/aks/create-nodepool-share.sh          # SHARE_MODE=time-sliced-4 (default)
./03-gpu-sharing-and-dra/aks/install-sharing-config.sh
kubectl apply -k 03-gpu-sharing-and-dra/aks/timeslicing
```
</details>

Expected: 4 replicas of `timeslice-demo`, all `Running` on **one** physical GPU node.
```
NAME                              READY   STATUS    NODE
timeslice-demo-7c9d8-2x4mz        1/1     Running   gke-...-l4-timeshare-spot-...
timeslice-demo-7c9d8-8kq2n        1/1     Running   gke-...-l4-timeshare-spot-...
timeslice-demo-7c9d8-tl5vw        1/1     Running   gke-...-l4-timeshare-spot-...
timeslice-demo-7c9d8-x9k2q        1/1     Running   gke-...-l4-timeshare-spot-...
```
`nvidia-smi -L` in any pod shows the same GPU UUID from all four — confirm it with
`kubectl -n ch03-gpu-sharing get pods -o wide | grep timeslice` then `nvidia-smi` in two
different pods.

### Step 2: MPS

What you're about to do: create a GPU node pool with MPS sharing enabled, point 4 pods at the same
physical GPU through a shared CUDA context, and confirm the plugin injects `CUDA_MPS_*` env vars —
proof each pod is going through MPS, not a private GPU.

<details><summary>GKE</summary>

```bash
./03-gpu-sharing-and-dra/gke/create-nodepool-mps.sh   # l4-mps-spot, gpu-sharing-strategy=mps, 4 clients/GPU
kubectl apply -k 03-gpu-sharing-and-dra/gke/mps
kubectl -n ch03-gpu-sharing get pods -o wide
```
Expected output:
```
NAME                         READY   STATUS    NODE
mps-demo-7c9d8-2x4mz         1/1     Running   gke-...-l4-mps-spot-...
mps-demo-7c9d8-8kq2n         1/1     Running   gke-...-l4-mps-spot-...
mps-demo-7c9d8-tl5vw         1/1     Running   gke-...-l4-mps-spot-...
mps-demo-7c9d8-x9k2q         1/1     Running   gke-...-l4-mps-spot-...
```
How to tell this worked: all 4 pods are `Running` on the same node (`gke-...-l4-mps-spot-...`), and
each has `hostIPC: true` set (GKE's managed MPS requires it — see the overlay's patch).

</details>

<details><summary>EKS</summary>

```bash
./03-gpu-sharing-and-dra/eks/create-nodegroups.sh gpu-share-spot   # ships labeled time-sliced-4 by default
kubectl label node -l course-chapter=03,eks.amazonaws.com/nodegroup=gpu-share-spot \
  nvidia.com/device-plugin.config=mps-4 --overwrite
./03-gpu-sharing-and-dra/eks/install-sharing-config.sh
kubectl apply -k 03-gpu-sharing-and-dra/eks/mps
kubectl -n ch03-gpu-sharing get pods -o wide
```
Expected output: same 4-pod `Running` table as GKE, all on the one `gpu-share-spot` node.
How to tell this worked: `kubectl get nodes -o custom-columns=NAME:.metadata.name,CFG:.metadata.labels.nvidia\.com/device-plugin\.config`
shows `mps-4` on that node, not `time-sliced-4`.

</details>

<details><summary>AKS</summary>

```bash
SHARE_MODE=mps-4 ./03-gpu-sharing-and-dra/aks/create-nodepool-share.sh
./03-gpu-sharing-and-dra/aks/install-sharing-config.sh
kubectl apply -k 03-gpu-sharing-and-dra/aks/mps
kubectl -n ch03-gpu-sharing get pods -o wide
```
Expected output: same 4-pod `Running` table, all on the `gpushare` node.
How to tell this worked: the node is labeled `nvidia.com/device-plugin.config=mps-4`
(`az aks nodepool show ... --query nodeLabels` or `kubectl get nodes -L nvidia.com/device-plugin.config`).

</details>

Verify on any cloud — each pod sees `CUDA_MPS_*` env vars injected by the plugin, proof it's going
through MPS and not a private full GPU:
```bash
kubectl -n ch03-gpu-sharing logs deploy/mps-demo | grep CUDA_MPS
```
Expected output:
```
CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
```

### Step 3: DRA

What you're about to do: install the NVIDIA DRA driver on its own node pool (never mixed with a
device plugin), apply the four claim patterns from `common/dra/`, and confirm the scheduler allocated
real devices through `ResourceClaim`/`ResourceSlice` objects instead of extended-resource counting.

<details><summary>GKE</summary>

```bash
./03-gpu-sharing-and-dra/gke/create-nodepool-dra.sh    # l4-dra-spot, driver disabled, DRA-only labels
kubectl -n kube-system rollout status ds/nvidia-driver-installer
./03-gpu-sharing-and-dra/gke/install-dra-driver.sh
kubectl apply -k 03-gpu-sharing-and-dra/gke/dra
kubectl get resourceclaims -n ch03-gpu-sharing
kubectl get resourceslices -o wide
```
Expected output:
```
NAME                    STATE
dra-cpu-single-...      allocated,reserved
```
```
NAME                  NODE               DRIVER
gke-...-l4-dra-spot   gke-...-l4-dra...  gpu.nvidia.com
```
How to tell this worked: every claim in `kubectl get resourceclaims -n ch03-gpu-sharing` shows
`allocated,reserved`, and `kubectl get deviceclass` lists `gpu.nvidia.com`.

</details>

<details><summary>EKS</summary>

```bash
./03-gpu-sharing-and-dra/eks/create-nodegroups.sh gpu-dra-spot
./03-gpu-sharing-and-dra/eks/install-dra-driver.sh
kubectl apply -k 03-gpu-sharing-and-dra/eks/dra
kubectl get resourceclaims -n ch03-gpu-sharing
kubectl get resourceslices -o wide
```
Expected output: same `allocated,reserved` claim state and a `ResourceSlice` with `DRIVER
gpu.nvidia.com` on the `gpu-dra-spot` node.
How to tell this worked: `kubectl get ds -n gpu-operator -o wide` shows **no** device-plugin
DaemonSet pod on the `gpu-dra-spot` node (label `gpu-mode=dra` keeps it off), only the DRA
kubelet plugin.

</details>

<details><summary>AKS</summary>

```bash
./03-gpu-sharing-and-dra/aks/create-nodepool-dra.sh    # gpudra, --gpu-driver none
./03-gpu-sharing-and-dra/aks/install-dra-driver.sh
kubectl apply -k 03-gpu-sharing-and-dra/aks/dra
kubectl get resourceclaims -n ch03-gpu-sharing
kubectl get resourceslices -o wide
```
Expected output: same `allocated,reserved` claim state and a `ResourceSlice` with `DRIVER
gpu.nvidia.com` on the `gpudra` node.
How to tell this worked: same as EKS — no device plugin on the `gpudra` node
(`kubeletPlugin.nodeSelector={"gpu-mode":"dra"}` keeps the DRA plugin off the sharing/MIG pools
and vice versa).

</details>

Inspect what the driver published on any cloud: `kubectl get resourceslice -o yaml | less` —
attribute names (e.g. `memory`) are what `03-cel-selector.yaml`'s CEL expression matches against.

### Step 4: MIG (advanced, needs A100/H100/H200 quota)

<details><summary>GKE</summary>

```bash
./03-gpu-sharing-and-dra/gke/create-nodepool-mig.sh   # PARTITION=1g.5gb default
kubectl apply -k 03-gpu-sharing-and-dra/gke/mig
```
</details>

<details><summary>EKS</summary>

```bash
./03-gpu-sharing-and-dra/eks/create-nodegroups.sh gpu-mig-spot
# MIG Manager (part of the GPU Operator) reads the nvidia.com/mig.config label and partitions
# the GPU after the node joins; wait for it before scheduling:
kubectl get pods -n gpu-operator -l app=nvidia-mig-manager -w
kubectl apply -k 03-gpu-sharing-and-dra/eks/mig
```
</details>

<details><summary>AKS</summary>

```bash
./03-gpu-sharing-and-dra/aks/create-nodepool-mig.sh   # PROFILE=MIG1g, immutable after creation
# AKS's own driver install does NOT deploy a device plugin. Install one with MIG_STRATEGY=single:
helm install nvdp nvdp/nvidia-device-plugin --version=0.17.0 \
  --set migStrategy=single --set gfd.enabled=true \
  --namespace nvidia-device-plugin --create-namespace
kubectl apply -k 03-gpu-sharing-and-dra/aks/mig
```
</details>

Expected: `kubectl describe node <mig-node> | grep -A3 Allocatable` shows `nvidia.com/gpu: 7`
(1g.5gb on a 40GB A100). `nvidia-smi -L` inside a pod shows the parent GPU plus exactly one MIG
device — every pod gets a different one, verified isolation, not oversubscription.

## 5. Spot considerations

- **Sharing amplifies spot's blast radius.** One preemption now interrupts 4 (time-slicing/MPS)
  or 7 (MIG 1g.5gb) workloads instead of 1. Keep replicas/retries per workload, not just per node.
- **MIG spot capacity is scarce.** A100/H100 spot/preemptible availability is far lower than
  L4/T4 — expect longer waits or fall back to on-demand (`ON_DEMAND=true` in every script here)
  and delete the pool immediately after the lab.
- **DRA node pools scale like any other spot pool** — `min 0`/`desiredCapacity 0` everywhere in
  this chapter's scripts. A pending `ResourceClaim` scales the pool up on GKE/AKS (built-in
  autoscaler); on EKS scale the node group manually or wait for chapter 13 (Karpenter).
- **On-demand fallback**: every `create-nodepool-*`/`create-nodegroups.sh` script here honors
  `ON_DEMAND=true` (drops `--spot`/`spot: true`/`--priority Spot`).

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pod `FailedPrepareDynamicResources` / stuck `ContainerCreating` (DRA) | DRA driver feature gate not enabled (e.g. `TimeSlicingSettings`) or driver/device-plugin both on the node | Check `helm get values nvidia-dra-driver-gpu -n nvidia-dra-driver-gpu`; confirm no device plugin DaemonSet on that node (`kubectl get ds -n gpu-operator -o wide`) |
| `0/1 nodes are available: 1 Insufficient nvidia.com/gpu` after enabling sharing | Node still labeled with the old / no `nvidia.com/device-plugin.config`, plugin didn't restart | `kubectl label node <node> nvidia.com/device-plugin.config=time-sliced-4 --overwrite`; GPU Operator's config-manager restarts the plugin automatically, static installs need a manual `kubectl rollout restart ds/nvidia-device-plugin` |
| MPS pod never sees `CUDA_MPS_*` env | Plugin's MPS control daemon not running, or (GKE) missing `hostIPC: true` | `kubectl -n gpu-operator logs -l app=nvidia-device-plugin-mps-control-daemon`; on GKE check the pod spec has `hostIPC: true` |
| AKS MIG node: `nvidia.com/gpu` shows 0 or missing after node Ready | No device plugin installed — `--gpu-driver Install`/`none` only installs the driver | Install `nvdp/nvidia-device-plugin` with `migStrategy` set (Step 4) |
| `ResourceClaim` stuck `pending` forever (no error) | No node in range advertises a matching `ResourceSlice`, or CEL selector too strict | `kubectl get resourceslices -o yaml`, check `device.capacity` names/units match the CEL expression exactly |
| EKS/AKS device plugin ConfigMap change has no effect | Wrong `devicePlugin.config.name`/`default` on the Helm release, or node missing the label | Re-run `install-sharing-config.sh`; verify with `kubectl get nodes -o custom-columns=NAME:.metadata.name,CFG:.metadata.labels.nvidia\.com/device-plugin\.config` |
| kind cluster: `no matches for kind "ResourceClaimTemplate"` | kind node image too old (pre-1.34) or wrong context | Recreate with `create-kind-cluster.sh` (pins `kindest/node:v1.35.8`); `kubectl config current-context` should be `kind-dra-cpu-lab` |

## 7. Cleanup and cost notes

```bash
./03-gpu-sharing-and-dra/gke/cleanup.sh
./03-gpu-sharing-and-dra/eks/cleanup.sh
./03-gpu-sharing-and-dra/aks/cleanup.sh
./03-gpu-sharing-and-dra/cpu-lab/cleanup.sh   # local, but frees laptop CPU/RAM
```
- Sharing doesn't change the node's hourly price — 4 time-sliced pods on one spot L4 still cost
  exactly what the node costs, split across more work. The saving is utilization, not the bill.
- MIG on A100/H100 spot, when available, is still several×  an L4/T4's price. Delete the pool the
  moment the lab is done; don't leave `min-count` above 0 overnight.
- The kind lab is entirely local — no cloud spend, but the driver's fake devices vanish with the
  cluster, so nothing lingers to bill you even if you forget cleanup.

## 8. Checkpoint questions

1. Why does MIG give the strongest isolation of the three sharing modes, and what's the cost of that?
2. Why do EKS and AKS have almost identical sharing manifests while GKE's look different?
3. What single rule must always hold between a DRA driver and a device plugin, and why?
4. What can a DRA `ResourceClaim`'s CEL selector express that a plain `nvidia.com/gpu: 1` request cannot?
5. What happens if two pods reference the same `ResourceClaim` by name (not a template)?
6. Why is MIG's partition size immutable after node-pool creation on every cloud?
7. Name one thing that doesn't carry over from the kind DRA lab to a real GPU cluster.

<details>
<summary>Answers</summary>

1. It physically partitions the GPU's SMs and memory into independent instances with their own
   fault domain — a crash or memory overrun in one MIG slice can't affect another. The cost:
   fixed partition sizes chosen at node creation, and it only exists on A100/H100/H200-class GPUs.
2. Neither EKS nor AKS have a native `gcloud`-style flag for GPU sharing on `az aks nodepool add`/
   `eksctl`; both rely on the same portable mechanism, the NVIDIA device plugin's `sharing:`
   ConfigMap. GKE bakes sharing into the node pool creation command itself.
3. They must never run on the same node — both hand out and account for the same physical GPU(s),
   and running both risks double-allocation or the scheduler's view of GPU capacity going out of
   sync with what's actually free.
4. Attribute/capacity-based matching, e.g. "any GPU with ≥20Gi memory" — something the
   extended-resource model can't express because `nvidia.com/gpu` is just an opaque count with no
   attached attributes the scheduler can filter on.
5. All pods referencing that claim by name land on the node holding the allocated device and share
   the same underlying GPU — "user-mediated" sharing, with no isolation between them (same as
   time-slicing but explicit and claim-based, not device-plugin-config-based).
6. The GPU's physical SM/memory partitioning happens once, when the driver configures the card
   for that profile; changing it requires the GPU to be reset/reconfigured, so every cloud
   requires deleting and recreating the node pool instead of live-editing it.
7. No real CUDA context, no device driver, no memory/compute isolation, no performance numbers —
   only the Kubernetes API objects (ResourceClaim/Template/DeviceClass) and scheduling flow
   transfer; anything that touches an actual GPU does not.
</details>

## 9. Further reading and versions tested

- [NVIDIA GPU sharing docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html), [NVIDIA MPS](https://docs.nvidia.com/deploy/mps/index.html), [Kubernetes DRA tutorial](https://kubernetes.io/docs/tutorials/cluster-management/install-use-dra/), [Kubernetes DRA concepts](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/)
- GKE: [Time-sharing GPUs](https://cloud.google.com/kubernetes-engine/docs/how-to/timesharing-gpus), [Multi-instance GPUs](https://cloud.google.com/kubernetes-engine/docs/how-to/gpu-multi-instance-gpu), [MPS](https://cloud.google.com/kubernetes-engine/docs/how-to/nvidia-mps-gpus), [DRA on GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/set-up-dra)
- EKS: [Amazon EKS GPU nodes](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html), [NVIDIA GPU Operator on EKS](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- AKS: [Multi-instance GPU](https://learn.microsoft.com/azure/aks/gpu-multi-instance), [AKS-managed GPU node pools](https://learn.microsoft.com/azure/aks/aks-managed-gpu-nodes), [az aks nodepool add reference](https://learn.microsoft.com/cli/azure/aks/nodepool)
- [`kubernetes-sigs/dra-example-driver`](https://github.com/kubernetes-sigs/dra-example-driver), [`kubernetes-sigs/dra-driver-nvidia-gpu`](https://github.com/NVIDIA/k8s-dra-driver-gpu) (moved from `NVIDIA/` org; chart now under `registry.k8s.io/dra-driver-nvidia`)

**Versions tested** (2026-09-16): Kubernetes 1.35 (`resource.k8s.io/v1` GA), GPU Operator
`${GPU_OPERATOR_VERSION}` (v26.7.0), NVIDIA device plugin `${DEVICE_PLUGIN_VERSION}` (v0.20.0),
`dra-driver-nvidia-gpu` chart `0.5.0` (`registry.k8s.io/dra-driver-nvidia`, not pinned in
`versions.env` yet — see `# VERIFY` items below), `dra-example-driver` `v0.5.0`, kind `v0.30+`,
`kindest/node:v1.35.8`, images `nvidia/cuda:12.9.1-base-ubuntu24.04`,
`nvcr.io/nvidia/k8s/cuda-sample:nbody-cuda11.7.1-ubuntu18.04`, `ubuntu:22.04`.
