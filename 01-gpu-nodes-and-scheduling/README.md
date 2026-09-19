# 01 · GPU Nodes and Scheduling

> How a GPU actually reaches a Pod: node images, drivers, the device plugin, extended resources, and
> the labels/taints/tolerations you need on EKS. Ends with a real CUDA job on a spot GPU node.

## Before you start

Needs from [`00-prerequisites-and-cluster-setup`](../00-prerequisites-and-cluster-setup): a cluster
with a spot CPU pool up (Step 4), tools verified (Step 1), `env.sh`/`versions.env` sourced, and GPU
quota approved on at least one cloud (Step 2) — this chapter creates the first real GPU node pool, so
without quota the pool stays at 0 nodes forever. If you only did the fake-GPU drill in chapter 00,
this chapter's Step 2 (cpu-lab) works without any of that.

## 1. Why this matters

`nvidia.com/gpu: 1` in a pod spec looks like any other resource request, but nothing about it is
built into Kubernetes. The scheduler only knows about **extended resources**: opaque integer
counters a **device plugin** registers with the kubelet. Get any link in this chain wrong — no
driver, no plugin, wrong taint, missing toleration — and a pod sits `Pending` or `CrashLoopBackOff`
with an error that doesn't mention the real cause. This chapter builds the chain up one link at a
time, on real (spot) GPU nodes, so when it breaks later in the course you know exactly where to look.

## 2. Learning objectives and time plan (~3 h)

By the end you can:

1. Explain the four things a GPU node needs before a pod can use `nvidia.com/gpu`: driver, container
   runtime/toolkit integration, device plugin, and scheduler-visible labels/taints.
2. Read `kubectl describe node` and explain every GPU-related label, taint, and allocatable field.
3. Create a spot GPU managed node group on EKS and run a real CUDA job on it.
4. Explain how EKS ships the driver (baked into the AMI), and what that means for chapter 02.
5. Debug the four or five most common "GPU pod stuck" failure modes without guessing.

| Time | Activity |
|---|---|
| 0:00–0:30 | Read section 3 (concepts). Skim `common/` manifests |
| 0:30–1:15 | Create a GPU node group, install the device plugin |
| 1:15–1:45 | Run `nvidia-smi-pod` and `cuda-vectoradd-job`, read `kubectl describe node` |
| 1:45–2:15 | `cpu-lab/scheduling-drills.yaml` — predict-then-run the taint/toleration/nodeSelector drills |
| 2:15–2:45 | Break things on purpose (remove a toleration, request 0.5 GPU, scale to 2 replicas on a 1-GPU pool) |
| 2:45–3:00 | Checkpoint questions, cleanup |

## 3. Concepts

### 3.1 The chain from silicon to Pod

```mermaid
flowchart TD
  subgraph Node["GPU node"]
    HW[NVIDIA GPU hardware]
    DRV[Kernel driver + CUDA user-mode libs]
    RT["Container runtime + NVIDIA integration<br/>(nvidia-container-toolkit / CDI)"]
    DP["Device plugin DaemonSet<br/>(kubelet gRPC: ListAndWatch, Allocate)"]
    KUBELET[kubelet]
    HW --> DRV --> RT
    DP -- registers nvidia.com/gpu=N --> KUBELET
    RT -.injects device + libs at container start.-> POD
  end
  API[kube-apiserver / scheduler] -- Pod requests nvidia.com/gpu:1 --> KUBELET
  KUBELET -- Allocate RPC --> DP
  DP -- device IDs --> KUBELET
  KUBELET --> POD[Container: sees /dev/nvidia*, driver libs]
```

- **Driver**: kernel module + CUDA user-mode libraries. Installed differently per cloud (3.2).
- **Container runtime integration**: makes `/dev/nvidia*` and driver libraries appear inside the
  container. Modern stacks use **CDI** (Container Device Interface, the current default in the
  NVIDIA Container Toolkit); older ones use the legacy `nvidia-container-runtime` hook.
- **Device plugin**: a DaemonSet that talks to the kubelet over a Unix-socket gRPC API
  (`ListAndWatch` reports available devices, `Allocate` is called when a pod using the resource is
  admitted). This is what turns physical GPUs into the extended resource `nvidia.com/gpu`.
- **Extended resource**: the scheduler treats `nvidia.com/gpu` exactly like `cpu`/`memory` counting
  — it is **opaque and integer-only**, can't be overcommitted, and `requests` must equal `limits`
  (Kubernetes rejects anything else for extended resources; see `00-prerequisites-and-cluster-setup`
  fake-GPU lab for the same rule with a fake resource).

### 3.2 Who installs the driver

| | EKS |
|---|---|
| Driver install | Baked into the **AL2023 NVIDIA-accelerated AMI** (`amiFamily: AmazonLinux2023` + a GPU instance type); driver, CUDA libs, nvidia-container-toolkit preinstalled by `nodeadm` |
| Container toolkit | Preinstalled on the AL2023 NVIDIA AMI |
| Device plugin | **Not installed** (this chapter installs a pinned one) |
| Skip the driver (for chapter 02, GPU Operator) | N/A — the AMI always has one; the Operator installs on top with `driver.enabled=false` |

This chapter uses EKS's own driver path (baked into the AMI). Chapter 02 (NVIDIA GPU Operator)
replaces parts of this stack with a single Helm chart — useful when you want the same DCGM/GFD/MIG
story managed by one component instead of the AMI.

### 3.3 Labels, taints, tolerations

| | EKS (`spot-gpu` nodegroup) |
|---|---|
| GPU taint | `nvidia.com/gpu=present:NoSchedule` (set explicitly in `gpu-nodegroups.yaml`) |
| GPU label | `nvidia.com/gpu.present=true` (set at boot by `nodeadm` on the AL2023 NVIDIA AMI) |
| Spot label | `eks.amazonaws.com/capacityType=SPOT` |
| Spot taint (automatic?) | No |

Every pod in `common/` requests `nvidia.com/gpu: 1` with no cloud-specific fields; each cloud's
`kustomization.yaml` applies a JSON6902 patch (`patch-pod.yaml`, `patch-job.yaml`) adding the right
`nodeSelector` and `tolerations`. This mirrors how you'd do it for real workloads later in the course
(vLLM Deployments, Kueue-managed Jobs, …) — cloud differences live in a thin overlay, not the base.

## 4. Lab

```bash
cp env.sh.example env.sh   # if not already done in chapter 00
source env.sh && source versions.env
```

### Step 1: What's in `common/`

- `namespace.yaml` — `ch01-gpu`
- `nvidia-smi-pod.yaml` — proves the whole chain: scheduler → device-plugin allocation → driver libs
  and `/dev/nvidia*` visible in the container. `nvidia-smi` is **not baked into the image**; it comes
  from the host driver, injected by the container runtime/CDI.
- `cuda-vectoradd-job.yaml` — a real CUDA kernel (vector add) as a `Job` (`backoffLimit: 3`), so a
  spot preemption mid-run gets retried automatically.

Read them before applying anything — this is the entire cloud-agnostic surface.

What you're about to do next: create a real GPU node group on EKS, install a device plugin (the AMI
doesn't ship one), then run `nvidia-smi-pod` and `cuda-vectoradd-job` to prove the whole chain works
end to end.

Create the spot GPU managed node group (`INCLUDE=ondemand-gpu` also creates the on-demand fallback
defined in [`eks/gpu-nodegroups.yaml`](eks/gpu-nodegroups.yaml); existing groups are skipped):
```bash
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
INCLUDE="${INCLUDE:-spot-gpu}"
envsubst '${EKS_CLUSTER} ${AWS_REGION}' < 01-gpu-nodes-and-scheduling/eks/gpu-nodegroups.yaml \
  > 01-gpu-nodes-and-scheduling/eks/.gpu-nodegroups.rendered.yaml
eksctl create nodegroup -f 01-gpu-nodes-and-scheduling/eks/.gpu-nodegroups.rendered.yaml \
  --include "$INCLUDE" --install-nvidia-plugin=false
eksctl get nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION"
```
The AL2023 NVIDIA AMI ships the driver and toolkit; `--install-nvidia-plugin=false` (chapter 00's
cluster create and this node group) is intentional — we install a **pinned** plugin instead of
eksctl's unpinned default DaemonSet.

Install the pinned NVIDIA device plugin via Helm (do not combine with the GPU Operator, chapter 02,
or the DRA driver on the same nodes):
```bash
CHART_VERSION="${DEVICE_PLUGIN_VERSION#v}"
# If a nodegroup was ever created without --install-nvidia-plugin=false, remove eksctl's auto-installed
# static DaemonSet first: kubectl -n kube-system delete ds nvidia-device-plugin-daemonset
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin --force-update
helm repo update nvdp
helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin --create-namespace \
  --version "$CHART_VERSION" \
  -f 01-gpu-nodes-and-scheduling/eks/values-device-plugin.yaml
kubectl -n nvidia-device-plugin get ds
```

Scale the GPU group up (EKS has no autoscaler by default: `--nodes 0` later stops paying) and run
the workloads:
```bash
NG="${NG:-spot-gpu}"; NODES=1
eksctl scale nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --name "$NG" \
  --nodes "$NODES" --nodes-min 0 --nodes-max 1
kubectl get nodes -l eks.amazonaws.com/nodegroup="$NG" -L node.kubernetes.io/instance-type,eks.amazonaws.com/capacityType
kubectl apply -k 01-gpu-nodes-and-scheduling/eks
kubectl -n ch01-gpu get pods -w
```
Expected output:
```
NAME          READY   STATUS      RESTARTS
nvidia-smi    1/1     Running     0
cuda-vectoradd-xxxxx   0/1   Completed   0
```
How to tell this worked:
```bash
kubectl -n nvidia-device-plugin get ds
kubectl get nodes -l eks.amazonaws.com/nodegroup=spot-gpu -L nvidia.com/gpu.present,eks.amazonaws.com/capacityType
```
The `nvdp` DaemonSet shows `DESIRED == READY == 1`, and the node is labeled
`nvidia.com/gpu.present=true` and `eks.amazonaws.com/capacityType=SPOT`.

### Step 2: Fake-GPU scheduling drills (no GPU needed, any cluster)

What you're about to do: run five pods with different taint/toleration/selector combinations against
a fake `nvidia.com/gpu` node, and predict each one's fate before you look at the answer — this builds
scheduling intuition without spending on a real GPU. Run this whether or not your cloud GPU pool is
up. Prereq: `00-prerequisites-and-cluster-setup/cpu-lab/advertise-fake-gpu.sh` (patches a CPU node
to `nvidia.com/gpu: 2` + taint + `fake-gpu=true` label).

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
NODE=$NODE COUNT=2 00-prerequisites-and-cluster-setup/cpu-lab/advertise-fake-gpu.sh
kubectl apply -k 01-gpu-nodes-and-scheduling/cpu-lab
kubectl -n ch01-gpu get pods -l drill=gpu-scheduling
```
Expected output (after a few seconds):
```
NAME                          READY   STATUS    RESTARTS
a-no-toleration-xxxxx         0/1     Pending   0
b-wrong-model-xxxxx           0/1     Pending   0
c-correct-xxxxx                1/1     Running   0
d-cpu-pod-on-gpu-node-xxxxx    1/1     Running   0
```
How to tell this worked: `c-correct` and `d-cpu-pod-on-gpu-node` are `Running`, `a-no-toleration` and
`b-wrong-model` stay `Pending` (`kubectl -n ch01-gpu describe pod a-no-toleration-xxxxx | grep -A2
Events` shows the taint/selector reason). **Before** applying, predict each pod's fate — the file's
comments have the answer:
- `a-no-toleration` — `Pending`, untolerated taint
- `b-wrong-model` — `Pending`, nodeSelector doesn't match (simulates a GFD label from chapter 02)
- `c-correct` — `Running`
- `d-cpu-pod-on-gpu-node` — `Running`, **on the fake-GPU node**, without ever requesting a GPU: a
  toleration is *permission* to schedule there, not a request for the resource
- `e-overcommit` (commented out) — uncomment it: the API server rejects `requests != limits` for
  `nvidia.com/gpu` at admission time, before the scheduler ever sees it

```bash
kubectl delete -k 01-gpu-nodes-and-scheduling/cpu-lab
kubectl patch node "$NODE" --subresource=status --type=json \
  -p '[{"op":"remove","path":"/status/capacity/nvidia.com~1gpu"}]' || true
kubectl label node "$NODE" fake-gpu- || true
kubectl taint node "$NODE" nvidia.com/gpu=present:NoSchedule- || true
```

## 5. Spot considerations

- **A cold spot GPU node takes minutes, not seconds.** From 0 nodes: AMI boot (driver already baked
  in) + image pull is commonly 3–8 min. Don't confuse this with a broken device plugin when a pod
  sits `Pending` right after scale-up.
- **The `Job` matters more than the `Pod` here.** `cuda-vectoradd-job.yaml` has `backoffLimit: 3`
  specifically so a spot reclaim mid-run gets retried instead of failing the whole workload.
  `nvidia-smi-pod.yaml` is a bare Pod — spot preemption just kills it, no retry. Use Jobs (or higher
  controllers) for anything that must survive a reclaim.
- **The device plugin must tolerate the spot taint too**, not just your workload — check
  `values-device-plugin.yaml`'s `tolerations` if the plugin DaemonSet never schedules onto the spot
  GPU pool (`nvidia.com/gpu` never shows up as allocatable at all).
- **On-demand fallback**: `INCLUDE=ondemand-gpu` when creating the node group creates the second,
  non-spot nodegroup defined in `gpu-nodegroups.yaml`.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pod `Pending`: `0/N nodes are available: 1 Insufficient nvidia.com/gpu` | No node has an allocatable GPU yet — node group at 0, or device plugin not running | Scale the node group up; `kubectl -n nvidia-device-plugin get ds` |
| Pod `Pending`: `node(s) had untolerated taint {nvidia.com/gpu: present}` | Missing toleration | Use the `eks` overlay (`kubectl apply -k .../eks`), not `common/` directly |
| `nvidia-smi` pod: `command not found` or empty GPU list | Container runtime isn't injecting the device/driver (toolkit misconfigured, or driver not finished installing) | `kubectl describe node` → check `Allocatable`; wait for AMI init; re-check taints |
| Two device-plugin DaemonSets running, GPUs double-counted or flapping | `eksctl create nodegroup` ran without `--install-nvidia-plugin=false` | `kubectl -n kube-system delete ds nvidia-device-plugin-daemonset`, keep only the pinned `nvdp` one |
| Pod requesting `nvidia.com/gpu: 0.5` rejected at `kubectl apply` | Extended resources are integer-only | Request whole GPUs; see chapter 03 for MPS/time-slicing/MIG fractional sharing |
| `nvidia.com/gpu` request accepted with `limits != requests` | It isn't — the API server always rejects this for extended resources | N/A, this is expected; see `cpu-lab` drill `e-overcommit` |

## 7. Cleanup and cost notes

```bash
kubectl delete -k 01-gpu-nodes-and-scheduling/eks --ignore-not-found
for ng in spot-gpu ondemand-gpu; do
  eksctl scale nodegroup --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --name "$ng" --nodes 0 --nodes-min 0 2>/dev/null || true
done
helm -n nvidia-device-plugin uninstall nvdp   # if you'll let the GPU Operator (ch02) manage the same nodes
```
- A single G4dn/G6 spot node is usually tens of cents/hour; on-demand is 2–4× that. **EKS does not
  autoscale** — a forgotten `desiredCapacity: 1` GPU node keeps billing until you scale it to 0.
- If you'll use the NVIDIA GPU Operator next chapter on the **same** nodes, uninstall this chapter's
  device plugin first — never run two device plugins.

## 8. Checkpoint questions

<details>
<summary>1. Why is <code>nvidia.com/gpu</code> called an "extended resource," and what two constraints does the API server enforce on it that don't apply to <code>cpu</code>/<code>memory</code>?</summary>

It's opaque (the scheduler just counts it, it doesn't understand "GPU") and comes from a device
plugin rather than being built into kubelet. The API server requires it to be an **integer** and
requires **`requests == limits`** (no overcommit, no fractional requests) — `cpu`/`memory` allow
fractional values and `requests < limits`.
</details>

<details>
<summary>2. Which two components does the device plugin sit between, and which gRPC call actually assigns device IDs to a pod?</summary>

Between the **kubelet** and the **container runtime's device injection**. `ListAndWatch` reports
available devices to the kubelet continuously; **`Allocate`** is called when a pod requesting the
resource is being admitted, and returns the actual device IDs/mounts for that pod.
</details>

<details>
<summary>3. Why does chapter 00's cluster create and this chapter's node-group create both pass <code>--install-nvidia-plugin=false</code>?</summary>

`eksctl` auto-installs an **unpinned** device-plugin DaemonSet on GPU nodegroups by default. This
repo pins every component's version (`versions.env`), so we disable that and install a specific
`DEVICE_PLUGIN_VERSION` via Helm instead. Leaving both on double-registers GPUs.
</details>

<details>
<summary>4. Why doesn't this chapter need to set <code>nvidia.com/gpu.present</code> by hand, the way an AKS-style setup would?</summary>

The device-plugin chart's default node affinity looks for an NFD label or `nvidia.com/gpu.present`.
EKS's AL2023 NVIDIA AMI sets `nvidia.com/gpu.present=true` at boot via `nodeadm`, automatically — no
cloud with an NFD-less driver install (like AKS) can rely on that and has to set the label explicitly.
</details>

<details>
<summary>5. A pod tolerates the GPU taint, sets no <code>resources.limits</code>, and gets scheduled onto your one spot GPU node. What happened, and why is this dangerous?</summary>

A toleration only removes a scheduling **restriction** — it does not request the resource. The pod
never asked for `nvidia.com/gpu`, so nothing stopped it from landing on the (otherwise idle-looking)
GPU node and consuming CPU/memory there, on your most expensive node type, silently. See
`cpu-lab/scheduling-drills.yaml` pod `d-cpu-pod-on-gpu-node`. Guard against it later with
admission policy (chapter 14) rather than trusting every pod author.
</details>

<details>
<summary>6. Why does <code>cuda-vectoradd-job.yaml</code> use a <code>Job</code> with <code>backoffLimit: 3</code> instead of a bare <code>Pod</code>, specifically because of spot?</summary>

A spot reclaim kills the pod. A bare Pod just dies. A Job with retries re-creates the pod (up to
`backoffLimit`) so a mid-run preemption doesn't fail the whole workload — the comment in the manifest
also notes `podFailurePolicy` could exclude `DisruptionTarget` from counting against the limit at
all, covered properly in chapter 06 (Kueue).
</details>

<details>
<summary>7. EKS's driver comes baked into the AMI, not installed by a controllable mechanism. What does that mean for chapter 02's GPU Operator?</summary>

You can't "disable" a driver that's already on the AMI at boot the way you'd flip a create-time flag
on a cloud with a managed driver installer. Instead you just don't let the Operator try to manage the
driver on top of it (`driver.enabled=false` in chapter 02's EKS values).
</details>

<details>
<summary>8. You requested <code>nvidia.com/gpu: 0.5</code> in a pod spec. What happens and why?</summary>

The API server rejects the pod at admission — extended resources must be whole integers, there is no
fractional GPU at the Kubernetes resource-accounting layer. Fractional/shared GPU access (time-slicing,
MPS, MIG) is a device-plugin/driver-level feature layered on top, covered in chapter 03.
</details>

## 9. Further reading and versions tested

- Kubernetes: [Device Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/), [Extended Resources](https://kubernetes.io/docs/tasks/administer-cluster/extended-resource-node/), [Schedule GPUs](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
- NVIDIA: [k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin), [Container Toolkit / CDI](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/index.html)
- EKS: [EKS-optimized accelerated AMIs](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html), [eksctl GPU support](https://docs.aws.amazon.com/eks/latest/eksctl/gpu-support.html)
- Next: [`02-nvidia-gpu-operator`](../02-nvidia-gpu-operator) (the alternative way to manage this whole stack), [`03-gpu-sharing-and-dra`](../03-gpu-sharing-and-dra) (fractional/shared GPU access)

**Versions tested** (2026-09-16): Kubernetes 1.35, `DEVICE_PLUGIN_VERSION=v0.20.0` (NVIDIA/k8s-device-plugin,
Helm chart `nvdp/nvidia-device-plugin`), images `nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0`,
`nvidia/cuda:12.9.1-base-ubuntu24.04`, `busybox:1.37.0`, eksctl v0.230.0 schema.
