# 07 · Distributed Training with Kubeflow Trainer

> Running multi-node PyTorch DDP training as a first-class Kubernetes object with **Kubeflow
> Trainer v2** (`TrainJob` / `TrainingRuntime` / `ClusterTrainingRuntime`), gang-scheduled and
> checkpointed so it survives spot reclaims, on **EKS**.

---

## 0. Before you start

This chapter assumes:

- A cluster from `00-prerequisites-and-cluster-setup`, with the GPU node-pool mechanics from
  `01-gpu-nodes-and-scheduling` and the NVIDIA GPU Operator from `02-nvidia-gpu-operator` already
  understood — this chapter creates its own dedicated GPU node pool (§4.3) but assumes you know
  why the driver/device-plugin steps happen.
- Bucket-mount CSI drivers from `05-model-storage-and-data` (Mountpoint for S3) — this chapter's
  checkpoints use them.
- Optional: the `team-research` ClusterQueue from `06-batch-jobs-and-kueue` if you plan to run
  §3.4/Lab C — not required for the base GPU lab.
- `env.sh` and `versions.env` sourced.

## 1. Why this matters

### 1.0 If you've never done distributed training before, start here

Every chapter before this one ran **one pod, one job**. This chapter is the first one where a
single logical "job" is actually *several pods that must cooperate in real time*. If any of the
vocabulary below is new, read this section before touching a command — the lab will make a lot
more sense once you know what problem it's solving.

- **Why split training across machines at all?** A model's weights and the batch of data used to
  update them have to fit in one GPU's memory and be processed by one GPU's compute. When the
  model is too big, or you simply want to get through more training data per hour than one GPU
  can chew through, you split the work across multiple GPUs — possibly on multiple physical
  machines (nodes). This chapter's lab uses the simplest and most common split: **data
  parallelism**. The *same* model is copied onto every GPU; each GPU is handed a different slice
  of the batch, computes gradients on its slice, and then all GPUs average ("all-reduce") their
  gradients so every copy of the model stays identical after each step. (There are other splitting
  strategies — model/tensor/pipeline parallelism, for models too big for one GPU's memory — but
  this chapter doesn't use them; DDP is the one you'll meet first and most often.)
- **What is DDP?** `DistributedDataParallel` is PyTorch's built-in implementation of the data-
  parallel pattern above. Each GPU process is a "rank." All ranks run the identical training
  script; DDP wraps the model so that after each backward pass, it automatically triggers an
  **all-reduce** — a collective network operation where every rank exchanges its gradients with
  every other rank and they all end up with the same averaged gradient — over NCCL (NVIDIA's
  GPU-to-GPU communication library). No rank is "in charge" of the math; they're peers. But they
  do need one coordinator moment at startup, which is where rank 0 and rendezvous come in.
- **Rank, world size, rendezvous, `torchrun`**: `torchrun` is the PyTorch launcher that starts one
  training process per GPU and hands each one four pieces of information: its **rank** (0, 1, 2…
  — a unique ID for that process), the **world size** (total number of processes across *all*
  nodes — the group can't do anything until every one of them has shown up), and how to find
  **rank 0** (an IP/hostname + port, called `MASTER_ADDR`/`MASTER_PORT`) so every process can dial
  in and agree "we're all here, let's start." That handshake is the **rendezvous**. Once it
  completes, training proceeds in lockstep: every rank runs the same step number at (roughly) the
  same time, synchronized by the all-reduce after every backward pass.
- **Why this needs Kubernetes-native orchestration, not just a Deployment**: a plain Kubernetes
  Deployment or Job has no concept of "these N pods are one unit that must all start together, and
  all die together if one dies." Kubeflow Trainer exists to give you that: it creates exactly the
  right number of pods, injects the rendezvous info (`MASTER_ADDR`, rank, world size) into each one
  automatically, and — critically for this chapter — knows how to recreate *the whole group
  together* when one pod is lost, instead of leaving the survivors hung forever. §3.2 below covers
  exactly how.
- **Why losing one pod is worse here than anywhere else in this course**: in earlier chapters, a
  reclaimed pod running a stateless inference server just gets rescheduled and traffic resumes a
  few seconds later — no other pod cared that it briefly disappeared. In DDP, every rank is
  waiting on every other rank at every synchronization point. Lose the node under rank 1, and rank
  0 doesn't notice "one fewer worker" and carry on — it calls `all_reduce` and blocks forever
  waiting for a peer that no longer exists, until a timeout eventually kills it too. That's the
  core operational problem this chapter's `failurePolicy` and checkpointing solve.
- **What checkpointing buys you**: since one lost rank can force the *entire* gang to be recreated
  (§3.2), you want the fresh set of pods to pick up from the last saved point rather than starting
  the whole run over from step 0. A **checkpoint** is a snapshot of the model's weights (and
  optimizer state) written to durable storage periodically during training — §4.5 has you trigger
  a simulated reclaim against the real S3-backed checkpoint volume this chapter sets up in §4.3.

A distributed training run is not a bag of independent pods — it's a **gang**: `torchrun` needs
every rank up and rendezvoused before any of them can make progress, and if one rank dies the
whole NCCL process group is dead too. Plain Deployments/Jobs don't understand that. Kubeflow
Trainer v2 (the rewrite of the old `PyTorchJob`/`TFJob` operators, now generic across frameworks)
gives you:

- A **`TrainJob`** — the thing you submit, with `numNodes`, `numProcPerNode`, image, command and
  per-node resources, referencing a reusable **runtime**. Think of it as "run this training script
  across this many nodes/processes, using that runtime's rules for how to lay out and recover the
  pods." You'll write one of these per training run (§3.1, `eks/trainjob-ddp-gpu.yaml`).
- A **`ClusterTrainingRuntime`** / namespaced **`TrainingRuntime`** — the "platform team" contract:
  a reusable template that says *how* any TrainJob referencing it should be run — which framework
  plugin to use (PyTorch here), what failure/restart behavior to apply, what the pod template looks
  like. You write the TrainJob once per run; the runtime is written once and reused by many
  TrainJobs, the same way a Helm chart's `values.yaml` is written once and instantiated many times.
  It's built on a **JobSet** (one Kubernetes `batch/v1` Job per replicated node group, with a
  `failurePolicy` that can recreate the *whole* gang on a single lost pod), plus a plugin that
  injects `PET_*` env vars so `torchrun` needs zero rendezvous flags.
- A **`JobSet`** — a Kubernetes API (from the separate `jobset.sigs.k8s.io` project, installed as a
  CRD alongside Trainer) for exactly this "group of Jobs that succeed or fail together" pattern.
  Trainer doesn't reinvent gang scheduling — it generates a JobSet under the hood from your
  TrainJob + TrainingRuntime, and the JobSet controller is what actually creates the per-rank Jobs,
  watches them, and enforces the recreate-the-whole-gang policy. You won't write JobSet YAML
  directly in this chapter, but `kubectl get jobset` and `kubectl get jobs` (plural) are how you'll
  observe what Trainer built for you.
- **`runtimePatches`** — strategic-merge patches the `eks/` overlay layers onto the runtime's
  JobSet template without forking the runtime itself. That's how `eks/` adds its own node
  selectors/tolerations/volumes to the `torch-ddp-spot` runtime.

This is the DevOps translation of what an HPC scheduler's job step / gang-scheduling and
checkpoint-restart features do, expressed as Kubernetes CRDs. Chapter `06-batch-jobs-and-kueue`
covers the admission/quota layer this chapter's TrainJob is optionally submitted through; chapter
`05-model-storage-and-data` covers the bucket-mount CSI drivers this chapter's checkpoints use.

## 2. Learning objectives & time plan (~3 h)

By the end you can:

1. Explain the TrainJob → TrainingRuntime → JobSet chain and why gang failure handling
   (`failurePolicy.restartStrategy: Recreate`) is required for static-world-size DDP on spot.
2. Read and extend `eks/trainingruntime-torch-ddp-spot.yaml` and
   `eks/trainjob-ddp-gpu.yaml`.
3. Explain what the `runtimePatches` block does and why the GPU-taint and spot-taint
   tolerations it adds aren't automatic (EKS auto-taints neither — see
   `01-gpu-nodes-and-scheduling`).
4. Trigger a spot reclaim (or simulate one) mid-training and watch the DDP script's SIGTERM
   handling + JobSet's gang-recreate bring the run back to the last complete checkpoint.
5. Layer the `kueue/<cloud>` overlay on top and explain what changes once Kueue's ResourceFlavor,
   not a hardcoded nodeSelector, decides spot vs on-demand placement.
6. Calculate training memory footprints (weights, gradients, AdamW optimizer states) and justify
   when to switch from DDP to PyTorch FSDP or DeepSpeed ZeRO-1/2/3.
7. Explain AWS EFA hardware acceleration (OS bypass, SRD, GPUDirect RDMA) and configure critical
   production NCCL environment variables for Kubernetes.

| Block            | Time   | What                                                                               |
| ---------------- | ------ | ---------------------------------------------------------------------------------- |
| Theory           | 35 min | §3 concepts, TrainJob/runtime/JobSet object model                                  |
| Lab A            | 60 min | Install Trainer, GPU node pool, storage, run the 2-node DDP TrainJob on your cloud |
| Lab B            | 45 min | Kill a node / simulate spot reclaim, watch gang recreate + checkpoint resume       |
| Lab C (optional) | 20 min | Layer `kueue/<cloud>`, watch Kueue admit/suspend the TrainJob                      |
| Review           | 20 min | Troubleshooting, checkpoint questions, cleanup                                     |

## 3. Concepts

### 3.1 TrainJob, TrainingRuntime, JobSet

```mermaid
flowchart TB
    subgraph submit["you submit"]
        TJ["TrainJob ddp-gpu<br/>numNodes=2, numProcPerNode=1<br/>runtimeRef: torch-ddp-spot"]
    end
    subgraph platform["platform team ships"]
        TR["TrainingRuntime torch-ddp-spot<br/>mlPolicy.torch, failurePolicy.Recreate"]
    end
    subgraph overlay["TrainJob's own runtimePatches"]
        RP["nodeSelector / tolerations<br/>bucket-mount annotation"]
    end
    TJ -->|runtimeRef| TR
    TJ -->|"spec.runtimePatches[]"| RP
    TR --> JS["JobSet (1 replicatedJob: node)"]
    RP --> JS
    JS --> J0["Job node-0 (rank 0)"]
    JS --> J1["Job node-1 (rank 1)"]
    J0 --> P0["Pod: torchrun train_ddp.py<br/>PET_NODE_RANK=0"]
    J1 --> P1["Pod: torchrun train_ddp.py<br/>PET_NODE_RANK=1"]
    P0 <-.->|NCCL all-reduce| P1
```

**Reading this diagram if you've never seen a multi-pod training topology before**: follow it top
to bottom, then side to side at the bottom.

- **Top row (what you write)**: you author one `TrainJob` object. It doesn't describe pods
  directly — it just says "2 nodes, 1 process per node" and points at a runtime by name
  (`runtimeRef`).
- **Middle row (what the platform team already wrote)**: the `TrainingRuntime` it points at
  carries the actual pod template, image defaults, and — importantly — the failure-handling policy
  from §3.2. You didn't have to write any of that; you referenced it.
- **Side box (what the TrainJob itself adds)**: `eks/trainjob-ddp-gpu.yaml`'s own
  `spec.runtimePatches[]` layers a small patch on top of the shared runtime with spot node
  selectors and taint tolerations, without changing the runtime file itself — a Trainer-native
  way to keep one reusable runtime and vary only the placement rules per TrainJob.
- **The TrainJob + TrainingRuntime + patch together produce one JobSet** — this is the object
  Trainer actually creates in the cluster; you never write it by hand.
- **The JobSet creates one Kubernetes `Job` per rank** (`node-0`, `node-1` in this 2-node example)
  — each Job's `completionIndex` becomes that rank's `PET_NODE_RANK`. These are ordinary `batch/v1`
  Jobs; `kubectl get jobs -n ch07-training` will show exactly these two.
- **Each Job runs one pod**, and that pod runs `torchrun train_ddp.py` with `PET_*` env vars
  already injected — no manual `--rdzv-endpoint` flags.
- **The dashed line at the bottom (`NCCL all-reduce`) is the part that has nothing to do with
  Kubernetes** — once both pods are up, they talk to each other directly over the pod network using
  NCCL, exchanging gradients every training step. Kubernetes' job here is just to get both pods
  scheduled, networked, and named predictably (via the JobSet's headless Service, so
  `ddp-gpu-node-0-0.ddp-gpu` resolves to rank 0's pod IP) — it has no involvement in the actual
  training math after that.

The Trainer **torch plugin** reads `numNodes`/`numProcPerNode` off the TrainJob and injects
`PET_NNODES`, `PET_NPROC_PER_NODE`, `PET_NODE_RANK` (from the Job's completion index),
`PET_MASTER_ADDR` (`<trainjob>-node-0-0.<trainjob>`, the JobSet headless Service) and
`PET_MASTER_PORT=29500` into every pod — `torchrun /workspace/scripts/train_ddp.py` needs no
rendezvous flags at all (see `eks/trainjob-ddp-gpu.yaml`).

### 3.2 Gang failure handling

DDP's process group has a **fixed world size**. If rank 1's pod is evicted, rank 0 doesn't
degrade to "1 worker" — it hangs on the next `all_reduce` until NCCL's watchdog times out. Two
settings in `eks/trainingruntime-torch-ddp-spot.yaml` handle this:

- `backoffLimit: 0` on each replicated Job — one failed pod fails that Job immediately instead of
  retrying it alone (which would leave the *other* rank waiting).
- `failurePolicy.restartStrategy: Recreate`, `maxRestarts: 10` on the JobSet — recreates **every**
  Job (i.e. the whole gang) so all ranks re-rendezvous together. `terminationGracePeriodSeconds:
  25` gives `torchrun`'s SIGTERM handler (in `train_ddp.py`) time to `all_reduce` a stop signal
  and have rank 0 flush a final checkpoint before the pod is killed.
- `train_ddp.py` resumes from the newest checkpoint with a `.done` marker (see the script's
  docstring) — object stores have no atomic rename, so the `.pt` file is written first and the
  `.done` marker second; a reader only trusts a step once `.done` exists.

### 3.3 The TrainJob's own `runtimePatches`

`eks/trainingruntime-torch-ddp-spot.yaml` is the reusable runtime; `eks/trainjob-ddp-gpu.yaml`
carries its own `spec.runtimePatches[]` entry (a strategic-merge patch the Trainer controller
applies to the runtime's JobSet template at admission time) with the spot/GPU `nodeSelector` +
`tolerations` for this cloud.

|                     | EKS                                                       |
| ------------------- | --------------------------------------------------------- |
| GPU                 | 1x T4 (`g4dn.xlarge`)                                     |
| Spot nodeSelector   | `eks.amazonaws.com/capacityType: SPOT`                    |
| GPU taint added by  | this chapter's node-group create (§4.3), `nvidia.com/gpu` |
| Spot taint added by | nobody (opt-in)                                           |
| Checkpoint bucket   | S3 via Mountpoint CSI (IRSA)                              |

Apply the full lab with plain `kubectl apply -f` against the files under `eks/` — see §4.4 for the
explicit command sequence.

### 3.4 Optional: Kueue admission

Layering Kueue admission on top of the base GPU lab needs two changes, both done with plain
`kubectl` against the objects §4.4 already applied — no separate overlay directory:

- `kubectl apply -f eks/localqueue.yaml` creates a `LocalQueue` in this chapter's namespace,
  pointing at the `team-research` `ClusterQueue` from `06-batch-jobs-and-kueue`.
- Labeling the TrainJob `kueue.x-k8s.io/queue-name: ch07-queue` makes Kueue's admission webhook
  suspend it until the ClusterQueue has quota to admit it; once admitted, Kueue's own
  `runtimePatch` decides spot vs on-demand, so you also remove the hardcoded
  `eks.amazonaws.com/capacityType: SPOT` key from `eks/trainjob-ddp-gpu.yaml`'s `nodeSelector`
  (keeping the GPU-type selector and both tolerations) — otherwise the TrainJob would just sit
  `Pending` whenever spot is unavailable instead of falling back to on-demand.

```bash
kubectl apply -f 07-distributed-training-kubeflow-trainer/eks/localqueue.yaml
kubectl -n ch07-training label trainjob ddp-gpu kueue.x-k8s.io/queue-name=ch07-queue --overwrite
kubectl -n ch07-training patch trainjob ddp-gpu --type=json \
  -p='[{"op":"remove","path":"/spec/runtimePatches/0/trainingRuntimeSpec/template/spec/replicatedJobs/0/template/spec/template/spec/nodeSelector/eks.amazonaws.com~1capacityType"}]'
```

### 3.5 Real-world distributed training architectures: DDP vs. FSDP vs. DeepSpeed ZeRO

This chapter's lab runs standard PyTorch DDP (`DistributedDataParallel`). DDP is the right baseline to learn first because it is straightforward: every GPU holds a full copy of the model, and GPUs only exchange averaged gradients at each step. But in modern production LLM engineering, **DDP hits a hard ceiling when models exceed ~2–3 billion parameters**. Here is why, and what production teams use instead.

#### The memory math of training: why large models OOM on DDP

When training an LLM, GPU memory is consumed by four distinct components:

1. **Model parameters**: In half-precision (FP16 or BF16), each parameter takes 2 bytes. A 7B model takes $7 \times 10^9 \times 2 = 14\text{ GB}$ of VRAM just to store the weights.
2. **Gradients**: Gradients match parameter precision, taking another 2 bytes per parameter ($14\text{ GB}$).
3. **Optimizer states (the biggest memory hog)**: Production training uses the AdamW optimizer. AdamW maintains:
   - An FP32 master copy of weights (4 bytes/param) to prevent underflow during weight updates.
   - First momentum vector $m$ in FP32 (4 bytes/param).
   - Second momentum vector $v$ in FP32 (4 bytes/param).
   - Total optimizer state: $4 + 4 + 4 = 12\text{ bytes per parameter}$ (or 16 bytes/param if tracking FP32 gradients). For a 7B model, optimizer states alone take $7 \times 10^9 \times 12 = 84\text{ GB}$ of VRAM!
4. **Activations and KV buffers**: Memory needed to store intermediate layer outputs during the forward pass for backward backpropagation (proportional to sequence length, hidden dimension, and batch size).

$$
\text{Total Static State} = \text{Weights (2B)} + \text{Gradients (2B)} + \text{Optimizer States (12B)} = 16\text{ bytes per parameter}
$$

For a 7B model: $16 \times 7 = 112\text{ GB}$ of GPU memory is required **before computing a single token's activations**. On a standard 24 GB GPU (like an NVIDIA L4 or A10G), DDP cannot even load the model into memory.

#### PyTorch FSDP (Fully Sharded Data Parallel)

PyTorch FSDP (`torch.distributed.fsdp`) solves this by **sharding model states across all participating GPUs** rather than replicating them:

- **`FULL_SHARD` (ZeRO-3 equivalent)**: Parameters, gradients, and optimizer states are sharded across all ranks. If you have 8 GPUs, each GPU holds only $\frac{1}{8}$ of the weights, gradients, and optimizer states.
  - *Forward pass*: Rank $i$ issues an `all-gather` collective to temporarily reconstruct full layer weights for the current layer, computes the forward activations, and immediately discards the full weights.
  - *Backward pass*: Rank $i$ all-gathers the layer weights again, calculates gradients, performs a `reduce-scatter` to send gradient shards to their respective owners, and frees the weights.
- **`SHARD_GRAD_OP` (ZeRO-2 equivalent)**: Shards optimizer states and gradients across ranks, but retains full model weights on each GPU. Great when weights fit in memory but optimizer states cause OOM.
- **`HYBRID_SHARD`**: Shards parameters across GPUs *within the same physical node* (where ultra-fast NVLink is available), but runs standard DDP replication *across physical nodes* over the network. This minimizes cross-node network bandwidth while eliminating intra-node memory duplication.

#### DeepSpeed ZeRO (Zero Redundancy Optimizer)

DeepSpeed (by Microsoft) pioneered this sharding hierarchy:
- **ZeRO-Stage 1**: Shards AdamW optimizer states ($4\times$ memory reduction, zero extra communication volume).
- **ZeRO-Stage 2**: Shards optimizer states + gradients ($8\times$ memory reduction, zero extra communication volume).
- **ZeRO-Stage 3**: Shards optimizer states + gradients + model parameters (linear memory reduction with world size; introduces ~50% communication overhead due to all-gather in forward/backward passes).
- **ZeRO-Offload**: Offloads optimizer states or model parameters to host system CPU RAM or node-local NVMe SSDs via PCIe. This enables fine-tuning a 13B model on a single 24 GB consumer/L4 GPU.

| Paradigm             | Model Weights      | Gradients  | Optimizer States   | Extra Communication        | Max Model on 8x 24GB GPUs |
| -------------------- | ------------------ | ---------- | ------------------ | -------------------------- | ------------------------- |
| **DDP**              | Replicated         | Replicated | Replicated         | None (standard all-reduce) | ~1.5B params              |
| **FSDP / ZeRO-2**    | Replicated         | Sharded    | Sharded            | None                       | ~3B params                |
| **FSDP / ZeRO-3**    | Sharded            | Sharded    | Sharded            | +50% (all-gather layers)   | ~14B–20B params           |
| **ZeRO-3 + Offload** | Sharded (CPU/NVMe) | Sharded    | Sharded (CPU/NVMe) | High (PCIe transfer)       | ~30B+ params              |

In Kubeflow Trainer v2, you can switch from plain DDP to FSDP or DeepSpeed by configuring the PyTorch plugin in your `TrainingRuntime` or specifying an `accelerate_config.yaml` with `plugin: fsdp`.

---

### 3.6 High-performance network fabric: AWS EFA & NCCL production tuning

In distributed training, every backward pass must synchronize gradients across all nodes. On an 8-node cluster, a single step triggers hundreds of megabytes of collective network transfers (`all-reduce` or `reduce-scatter`). 

On standard cloud networking, traffic passes through the Linux TCP/IP kernel stack, causing high packet latency, CPU interrupts, and jitter. If node 7 experiences a 20 ms network hiccup, **every other node in the cluster stops and waits at the NCCL barrier**. This turns training into an expensive bottleneck where GPUs sit at 30% compute utilization waiting on network packets.

#### What AWS EFA (Elastic Fabric Adapter) adds

AWS EFA is a custom network interface card engineered specifically for scale-out HPC and machine learning workloads on EC2:

1. **OS-Bypass (Libfabric / `fi_provider="efa"`)**: Applications write network buffers directly to the EFA hardware without kernel context switches or copying data into Linux OS sockets.
2. **SRD (Scalable Reliable Datagram)**: Instead of TCP (which binds a stream to a single network path, causing head-of-line blocking on packet loss), AWS SRD spreads packets across hundreds of multi-path network routes simultaneously. It reorders packets in hardware at the receiver, delivering consistently low p99 tail latency.
3. **GPUDirect RDMA**: On high-end GPU instances (`p4d.24xlarge`, `p5.48xlarge`, `g6e.8xlarge+`), EFA bypasses the host CPU and system RAM completely. Data flows directly from the sending GPU's VRAM across the PCIe/NVLink bus to the EFA NIC, over the network fabric, and directly into the remote GPU's VRAM.

#### EKS cluster prerequisites for EFA

To leverage EFA in an EKS distributed training cluster:

1. **EC2 Placement Groups**: You must launch the GPU worker nodes inside an EC2 Placement Group with `strategy: cluster`. This guarantees nodes are placed physically adjacent in the AWS datacenter on the same network spine, eliminating inter-AZ and inter-switch latency.
2. **AWS EFA Device Plugin**: Deploy `aws-efa-k8s-device-plugin` on your EKS cluster so the kubelet can advertise `vpc.amazonaws.com/efa` resources:
   ```yaml
   resources:
     limits:
       nvidia.com/gpu: 8
       vpc.amazonaws.com/efa: 4   # Requests 4 EFA interfaces per pod
   ```
3. **HugePages and Shared Memory**: Mount `/dev/shm` (`emptyDir: { medium: Memory }`) and configure `ipcMode: host` if required by your MPI/NCCL stack.

#### Critical production NCCL environment variables

When running multi-node PyTorch training on Kubernetes, configure these environment variables in your container spec or `TrainingRuntime`:

```yaml
env:
  # 1. Output NCCL diagnostics at startup: verify which transport is selected
  - name: NCCL_DEBUG
    value: "INFO"
  - name: NCCL_DEBUG_SUBSYS
    value: "INIT,ENV,NET"
  # 2. Tell NCCL which network interface to bind (prevent picking docker0 or cilium_net)
  - name: NCCL_SOCKET_IFNAME
    value: "eth0"
  # 3. Libfabric and EFA configuration
  - name: FI_PROVIDER
    value: "efa"
  - name: FI_EFA_USE_DEVICE_RDMA
    value: "1"                  # 1 = GPUDirect RDMA enabled
  # 4. Tune NCCL ring buffer size (default 4MB; 8MB helps saturate 400G+ links)
  - name: NCCL_BUFFSIZE
    value: "8388608"
  # 5. Prevent peer-to-peer over PCIe if NVLink is absent or broken
  - name: NCCL_P2P_DISABLE
    value: "0"
  # 6. NCCL Watchdog Timeout (prevent silent hung processes on spot preemption)
  - name: TORCH_NCCL_HEARTBEAT_TIMEOUT_SEC
    value: "120"
```

> [!TIP]
> **How to verify EFA is actually active**: In the pod startup logs, look for:
> `NCCL INFO NET/OFI: Using provider efa` and `NCCL INFO Using network AWS Libfabric`.
> If you see `NCCL INFO Using network Socket`, your pods have silently fallen back to standard Linux TCP sockets, and your distributed training speed will be throttled by network latency.

## 4. Lab

### 4.1 Prereqs

`source env.sh` loads your AWS account/region/cluster name into shell variables every later
command references (`${EKS_CLUSTER}`, `${AWS_REGION}`, `${AWS_ACCOUNT_ID}`); `source versions.env`
loads the pinned component versions (`${KUBEFLOW_TRAINER_VERSION}`, `${KUEUE_VERSION}`) so you're
never typing a version number by hand where it could drift from what this chapter was tested
against.

```bash
cd kubernetes-ai-infrastructure
source env.sh && source versions.env
```

A running cluster from `00-prerequisites-and-cluster-setup`, and GPU quota for the table in §3.3
(spot **and** on-demand family — spot capacity can be unavailable). `kubectl get ns kubeflow-system`
should not yet exist (first run), or should already have Trainer installed — the `helm upgrade
--install` in 4.2 below is idempotent, so re-running it on a later pass is safe.

> **GPU quota check first.** Unlike CPU node groups, AWS gates GPU instance families
> (`g4dn.xlarge` here) behind an EC2 service quota that defaults to 0 for new accounts.
> If you skip ahead to §4.3 without checking, `eksctl create nodegroup` will succeed but the
> underlying Auto Scaling Group will silently fail to launch any instances — go to the EC2 console
> → Service Quotas → "All G and VT Spot Instance Requests" (or the on-demand equivalent) and
> request at least 16 vCPUs before starting the lab. Quota increases can take minutes to days to
> be approved, so do this before you plan to run the lab, not during it.

### 4.2 Install Kubeflow Trainer

What you're about to do: install the Trainer controller + JobSet CRDs via Helm, pinned to
`${KUBEFLOW_TRAINER_VERSION}`, and enable the built-in `torch-distributed` ClusterTrainingRuntime.
This is the one-time platform setup step — it installs the controller that watches for `TrainJob`
objects and turns them into JobSets, plus the CRDs (`TrainJob`, `TrainingRuntime`,
`ClusterTrainingRuntime`) that let `kubectl` understand those object types at all. You only need to
run this once per cluster; every TrainJob you submit afterwards (§4.4, and any future chapter that
reuses this cluster) reuses the same installed controller. `--set
runtimes.torchDistributed.enabled=true` is what makes the chart's post-install hook create the
built-in `torch-distributed` `ClusterTrainingRuntime` this chapter's own `torch-ddp-spot`
`TrainingRuntime` (§3.2) is modeled on — without that flag the CRDs would install but no runtime
would exist to reference.

```bash
: "${KUBEFLOW_TRAINER_VERSION:?source versions.env first}"
helm upgrade --install kubeflow-trainer oci://ghcr.io/kubeflow/charts/kubeflow-trainer \
  --namespace kubeflow-system --create-namespace \
  --version "${KUBEFLOW_TRAINER_VERSION#v}" \
  --set runtimes.torchDistributed.enabled=true \
  --wait --timeout 10m
kubectl -n kubeflow-system rollout status deploy --timeout=5m
kubectl get crd trainjobs.trainer.kubeflow.org trainingruntimes.trainer.kubeflow.org clustertrainingruntimes.trainer.kubeflow.org
# The runtimes are applied by a post-install hook Job; give it a moment if this is empty.
kubectl get clustertrainingruntimes
```

Expected output (tail):

```
customresourcedefinition.apiextensions.k8s.io/trainjobs.trainer.kubeflow.org created
clustertrainingruntime.trainer.kubeflow.org/torch-distributed created
```

How to tell this worked: `kubectl get clustertrainingruntimes` lists `torch-distributed`, and
`kubectl -n kubeflow-system get pods` shows the trainer-controller-manager `Running`.

### 4.3 GPU node group and checkpoint storage

What you're about to do: create a spot GPU managed node group (`CAPACITY=on-demand` creates the
fallback group instead; requires "All G and VT Spot Instance Requests" — or on-demand G/VT — vCPU
quota ≥ 16), then create the checkpoint bucket and wire up IRSA for the Mountpoint for S3 CSI
driver.

> **This step provisions billable GPU capacity infrastructure.** `desiredCapacity: 0` means the
> node group is created with zero running instances (no cost yet) — nodes only launch once
> something actually requests `nvidia.com/gpu` (§4.4). But once the TrainJob's pods are scheduled,
> you *are* paying for real GPU instances by the hour, spot or on-demand. Don't forget §7's cleanup
> when you're done for the day.

Why a dedicated node group instead of reusing `01-gpu-nodes-and-scheduling`'s: this chapter pins a
specific instance type (`g4dn.xlarge`, the cheapest single-GPU lab shape) and its own taint key/label
so the lab's node selector in §3.3 has something predictable to target, independent of whatever GPU
node pool an earlier chapter left behind. The **taint** (`nvidia.com/gpu=true:NoSchedule`) is what
stops *non-GPU* pods from accidentally landing on your expensive GPU nodes — only pods that
explicitly tolerate it (like this chapter's TrainJob pods, via the `eks/` overlay's
`runtimePatches`) can schedule there. EKS does not add this taint for you automatically, which is
why the node-group definition below sets it explicitly (see `01-gpu-nodes-and-scheduling` for the
full explanation of why that matters).

```bash
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
CAPACITY="${CAPACITY:-spot}"
if [[ "${CAPACITY}" == "spot" ]]; then NG=gpu-spot-l4; SPOT=true; else NG=gpu-ondemand-l4; SPOT=false; fi

cat <<YAML | eksctl create nodegroup -f -
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${EKS_CLUSTER}
  region: ${AWS_REGION}
managedNodeGroups:
  - name: ${NG}
    amiFamily: AmazonLinux2023          # eksctl picks the NVIDIA AL2023 AMI for GPU instance types
    instanceTypes: ["g4dn.xlarge"]
    spot: ${SPOT}
    minSize: 0
    desiredCapacity: 0
    maxSize: 2
    volumeSize: 100                     # the PyTorch CUDA image is ~4 GB compressed
    labels:
      ch07.lab/gpu: l4
    taints:
      - key: nvidia.com/gpu
        value: "true"
        effect: NoSchedule
    propagateASGTags: true              # lets Cluster Autoscaler scale this group from zero
    # efaEnabled: true                  # advanced: only on EFA-capable types (p4d/p5/g6e.8xlarge+)
YAML
```

Checkpoint storage — creates the S3 bucket, an IAM role for the Mountpoint for S3 CSI driver
(IRSA), installs/updates the add-on so it tolerates the GPU taint, then renders `eks/pv-pvc.yaml`'s
`${BUCKET_NAME}`/`${AWS_REGION}` placeholders with `envsubst` (same render-then-apply pattern as
`00-prerequisites-and-cluster-setup`'s `eks/cluster.yaml`):

This is the step that turns §1.0's "checkpointing buys you resumability" from theory into a real
volume the training pods can write to. Without it, a checkpoint written inside the pod would live
only in that pod's ephemeral filesystem — gone the instant the pod is deleted, which defeats the
entire point when a spot reclaim (§4.5) is exactly the moment you need that checkpoint to still
exist. IRSA (IAM Roles for Service Accounts) is what lets the Mountpoint-S3 CSI driver's pods
authenticate to AWS as a specific IAM role — scoped by the policy below to only this chapter's
bucket — instead of needing broad node-level AWS credentials. `--configuration-values
'{"node":{"tolerateAllTaints":true}}'` matters because the CSI driver's own node-level pods must
run *on* the tainted GPU nodes to mount the volume for the training pods there — without this flag
the driver's daemonset would refuse to schedule onto the same taint you just added in §4.3.

```bash
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}"
BUCKET="${BUCKET:-${AWS_ACCOUNT_ID}-ch07-checkpoints}"
ROLE_NAME="${ROLE_NAME:-${EKS_CLUSTER}-s3-csi-driver}"
POLICY_NAME="${POLICY_NAME:-${EKS_CLUSTER}-ch07-s3-checkpoints}"
HERE=07-distributed-training-kubeflow-trainer/eks

if ! aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

POLICY_DOC=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "MountpointFullBucketAccess", "Effect": "Allow", "Action": ["s3:ListBucket"],
     "Resource": ["arn:aws:s3:::${BUCKET}"]},
    {"Sid": "MountpointFullObjectAccess", "Effect": "Allow",
     "Action": ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:DeleteObject"],
     "Resource": ["arn:aws:s3:::${BUCKET}/*"]}
  ]
}
JSON
)
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1 || \
  aws iam create-policy --policy-name "${POLICY_NAME}" --policy-document "${POLICY_DOC}"

eksctl utils associate-iam-oidc-provider --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --approve
eksctl create iamserviceaccount \
  --name s3-csi-driver-sa --namespace kube-system \
  --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" \
  --attach-policy-arn "${POLICY_ARN}" \
  --role-name "${ROLE_NAME}" --role-only --approve

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
if aws eks describe-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws eks update-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver \
    --region "${AWS_REGION}" --service-account-role-arn "${ROLE_ARN}" \
    --configuration-values '{"node":{"tolerateAllTaints":true}}' --resolve-conflicts OVERWRITE
else
  aws eks create-addon --cluster-name "${EKS_CLUSTER}" --addon-name aws-mountpoint-s3-csi-driver \
    --region "${AWS_REGION}" --service-account-role-arn "${ROLE_ARN}" \
    --configuration-values '{"node":{"tolerateAllTaints":true}}'
fi

command -v envsubst >/dev/null || { echo "envsubst missing: brew install gettext"; exit 1; }
BUCKET_NAME="${BUCKET}" envsubst '${BUCKET_NAME} ${AWS_REGION}' < "${HERE}/pv-pvc.yaml" \
  > "${HERE}/.pv-pvc.rendered.yaml"
echo "Wrote ${HERE}/.pv-pvc.rendered.yaml"
```

### 4.4 Run the lab

What you're about to do: apply the flat `eks/` manifests (namespace, service account, training
script ConfigMap, checkpoint PV/PVC, patched runtime, TrainJob), watch the 2-rank DDP TrainJob
rendezvous and start writing checkpoints.

This is the moment everything from §3 and §4.2–4.3 comes together: `kubectl apply` creates the
namespace and supporting objects, then submits the `TrainJob`; the Trainer controller resolves its
`runtimeRef` against `torch-ddp-spot`, applies the TrainJob's own `runtimePatches`, then creates
the underlying JobSet, which in turn creates one `Job` per rank and one pod per Job. Every file
below is a complete, standalone manifest — order only matters because the namespace and the
ConfigMap/PV/PVC the runtime references need to exist before the objects that use them. The `-w`
(watch) flag on the second command lets you see that transition happen live instead of guessing —
you're watching Trainer's reconciliation, not just a static snapshot. The third command tails both
ranks' logs at once (`--prefix` labels each line with its source pod) so you can see rank 0 and
rank 1 progressing through training steps together, which is the visible proof that rendezvous
succeeded and both ranks are synchronized.

```bash
HERE=07-distributed-training-kubeflow-trainer/eks
kubectl apply -f "${HERE}/namespace.yaml"
kubectl apply -f "${HERE}/serviceaccount.yaml" \
  -f "${HERE}/configmap-train-script.yaml" \
  -f "${HERE}/.pv-pvc.rendered.yaml" \
  -f "${HERE}/trainingruntime-torch-ddp-spot.yaml" \
  -f "${HERE}/trainjob-ddp-gpu.yaml"
kubectl -n ch07-training get trainjob ddp-gpu -w   # Ctrl-C once JOBSSTATUS shows Running
kubectl -n ch07-training logs -l trainer.kubeflow.org/trainjob-ancestor-step=trainer -f --prefix
```

Expected log lines (rank 0):

```
[rank 0/2] world_size=2 device=cuda step=0/20000 loss=...
[rank 0/2] checkpoint written: /mnt/checkpoints/ddp-gpu/step-00000500.pt (+.done)
```

How to tell this worked: `kubectl -n ch07-training get pods` shows 2 `Running` pods (one per
rank) and neither log stream shows a NCCL timeout.

### 4.5 Simulate a reclaim

What you're about to do: delete the rank-1 pod to simulate a spot reclaim mid-run, and watch the
JobSet recreate the whole gang instead of just the one pod. From Kubernetes' point of view, a real
spot reclaim and `kubectl delete pod` look the same — a `Running` pod abruptly disappears without
a clean exit — so this rehearses the failure and recovery path without waiting for an actual,
unpredictable interruption. This is the single most important exercise in the chapter: it's where
§1.0's "one lost pod can kill the whole job" and §3.2's `Recreate` policy stop being theory.

```bash
kubectl -n ch07-training delete pod \
  "$(kubectl -n ch07-training get pod -o name | grep node-1)"
kubectl -n ch07-training get jobs -w   # Ctrl-C once both Jobs show a new, higher restart count
```

Expected: both `ddp-gpu-node-0` and `ddp-gpu-node-1` Jobs restart together (not just node-1).
How to tell this worked: rank 0's log picks up the newest `.done` checkpoint step instead of
restarting from `step=0` — the Job's `backoffLimit: 0` fails that Job fast, and the JobSet's
`Recreate` policy recreates **both** Jobs so all ranks re-rendezvous together.

### 4.6 On-demand fallback if spot GPU capacity is unavailable

This course targets real GPU hardware throughout — there's no CPU-only fallback lab. If §4.3's
spot node group can't get capacity (`InsufficientInstanceCapacity`, distinct from the quota problem
in §4.1's warning), re-run §4.3 with `CAPACITY=on-demand` to create the `gpu-ondemand-l4` node
group instead, then repeat §4.4 unchanged — the TrainJob's `nodeSelector` only pins
`ch07.lab/gpu: l4` and the GPU-taint toleration, not a specific node group, so it schedules onto
whichever GPU pool actually has running nodes:

```bash
CAPACITY=on-demand bash -c '
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
# same eksctl create nodegroup call as §4.3, but with spot: false and a different node-group name
'
```

How to tell this worked: `kubectl get nodes -l ch07.lab/gpu=l4 -L eks.amazonaws.com/capacityType`
shows a node with `CAPACITYTYPE=ON_DEMAND`, and §4.4's TrainJob pods schedule onto it exactly as
they did on spot — just at 2-4x the hourly cost (§7), so switch back to spot once capacity returns.

## 5. Spot considerations

- **Gang-recreate, not per-pod restart**: a lone new rank 1 can't rejoin an already-formed NCCL
  group at a different `MASTER_ADDR` epoch — recreating the JobSet's Jobs makes every rank re-run
  rendezvous together (§3.2).
- **Grace period budget**: `terminationGracePeriodSeconds: 25` assumes fast checkpoint writes
  (small demo model). Size this to your real checkpoint's upload time — EKS gives ~2 minutes of
  spot notice, so there's room to grow it.
- **`CHECKPOINT_EVERY`** trades reclaim cost against bucket PUT traffic — tune it for your model
  size in `eks/trainjob-ddp-gpu.yaml`.
- **On-demand fallback**: the plain `eks/trainjob-ddp-gpu.yaml` doesn't run mixed spot+on-demand —
  layer Kueue admission (§3.4) for that, or use §4.6's manual fallback.

## 6. Troubleshooting

| Symptom                                             | Likely cause                                                                           | Why this happens                                                                                                                                                                                                                                                                                                                                                                                                          | Fix                                                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| TrainJob stuck `Pending`/`Suspended` forever        | No `kueue-system` ClusterQueue admitting it (only if you applied the §3.4 Kueue steps) | Kueue's admission webhook suspends every TrainJob labeled with a `queue-name` until its `LocalQueue`/`ClusterQueue` has quota to admit it — if the ClusterQueue's ResourceFlavors don't map to any real, schedulable nodes (e.g. the GPU node group in §4.3 was never created), the TrainJob waits forever with no error, because from Kueue's perspective it's correctly waiting for capacity that simply never shows up | `kubectl get clusterqueue team-research -o yaml`, check spot+on-demand ResourceFlavors have real nodes    |
| Pods `Pending`, event `Insufficient nvidia.com/gpu` | GPU node group scaled to 0 and nothing has scaled it up yet, or GPU quota exhausted    | Kubernetes' scheduler can only place a pod on a node that already exists with the requested resource; a node group at `desiredCapacity: 0` (§4.3) has no such node until something (Cluster Autoscaler, or your own `eksctl scale nodegroup`) provisions one, and even then AWS itself will refuse to launch the instance if your account's EC2 GPU quota (§4.1) is exhausted                                             | `kubectl get nodes -l ...`, check the EC2 quota console                                                   |
| `clustertrainingruntimes` empty after install       | Post-install hook Job hasn't finished                                                  | The Helm chart doesn't create the built-in runtime object directly in its templates — it runs a Kubernetes Job (a Helm post-install hook) that applies the runtime manifests after the controller is up, so there's a real (usually short) window where the CRDs exist but no runtime object does yet                                                                                                                     | `kubectl -n kubeflow-system get job,pod`, re-run `kubectl get clustertrainingruntimes` after it completes |
| Rank 0 hangs on `all_reduce` after a delete         | Deleted rank 0 itself, or `Recreate` hasn't fired yet                                  | Deleting rank 0 removes the peer every other rank's `PET_MASTER_ADDR` points at, so nobody can complete rendezvous until the JobSet notices the failure and recreates the whole gang (§3.2) — if you're watching immediately after the delete, you're just seeing the (expected) gap before `Recreate` kicks in, not a stuck state                                                                                        | `kubectl -n ch07-training get jobs` — both Jobs should show a new generation                              |
| Checkpoint dir empty after resume                   | `.done` marker never written (grace period too short, or write raced eviction)         | The `.pt` payload and `.done` marker (§3.2) are two separate writes; if the pod is killed between them — because `terminationGracePeriodSeconds` was too short for the upload to finish — the reader on restart correctly ignores the incomplete step and falls back to the last step that *did* get a `.done` marker, which can look like "the checkpoint vanished" if you were watching the newest one                  | Check pod logs for `SIGTERM received`; increase `terminationGracePeriodSeconds`                           |
| Mountpoint S3 mount `permission denied`             | IRSA binding from §4.3's storage setup didn't propagate yet, or SA name mismatch       | IRSA works by federating a Kubernetes ServiceAccount's OIDC token to an IAM role via a trust policy; if the ServiceAccount name/namespace in the trust policy doesn't exactly match what the pod actually uses, or the CSI driver's pod started before the IAM role propagated through AWS's eventually-consistent IAM, the mount will be denied even though the setup commands "succeeded"                               | Re-run the storage setup commands; confirm `serviceAccountName: trainer` matches the binding's subject    |

## 7. Cleanup and cost notes

```bash
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"
HERE=07-distributed-training-kubeflow-trainer/eks
kubectl delete trainjobs --all -n ch07-training --ignore-not-found
kubectl delete -f "${HERE}/trainjob-ddp-gpu.yaml" --ignore-not-found
kubectl delete -f "${HERE}/trainingruntime-torch-ddp-spot.yaml" --ignore-not-found
kubectl delete -f "${HERE}/.pv-pvc.rendered.yaml" --ignore-not-found
kubectl delete -f "${HERE}/configmap-train-script.yaml" -f "${HERE}/serviceaccount.yaml" --ignore-not-found
kubectl delete -f "${HERE}/localqueue.yaml" --ignore-not-found   # only if you applied the §3.4 Kueue steps
kubectl delete -f "${HERE}/namespace.yaml" --ignore-not-found
for ng in gpu-spot-l4 gpu-ondemand-l4; do
  eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name "${ng}" --wait 2>/dev/null || true
done
helm uninstall kubeflow-trainer -n kubeflow-system   # only if you're done with the whole chapter
aws s3 rb "s3://${BUCKET:-${AWS_ACCOUNT_ID}-ch07-checkpoints}" --force   # only if you want checkpoints gone too
```

Deletes the TrainJob, applied manifests and the GPU node group(s) (scaled from 0, so idle cost is
near zero between runs — but 2 running L4 GPU nodes are **not** cheap; don't leave the lab
`Running` overnight). Checkpoint storage is kept unless you run the last line.

## 8. Checkpoint questions

<details><summary>1. Why does <code>backoffLimit: 0</code> on the replicated Job matter for DDP specifically, when it would be a bad default for a normal batch Job?</summary>

A normal Job's pods are independent — retrying just the failed one is fine. DDP's ranks form one
process group with a fixed world size; retrying only the failed rank in place would still leave
the *other* rank's NCCL call hung against a peer that restarted at a different rendezvous epoch.
`backoffLimit: 0` fails that Job fast so the JobSet-level `Recreate` policy can restart the whole
gang together instead.
</details>

<details><summary>2. What actually decides <code>PET_MASTER_ADDR</code>, and why doesn't <code>train_ddp.py</code> need a rendezvous flag?</summary>

The Trainer torch plugin sets it to the JobSet's headless Service DNS name for the node-0
replica (`<trainjob>-node-0-0.<trainjob>`) and injects it (with `PET_NNODES`, `PET_NODE_RANK`,
`PET_MASTER_PORT`) as `PET_*` env vars every `torchrun` process reads automatically.
</details>

<details><summary>3. Why is the checkpoint write split into a <code>.pt</code> file and a separate <code>.done</code> marker?</summary>

Object stores (GCS, S3, Azure Blob) have no atomic rename/overwrite the way a POSIX filesystem
does. Writing the payload first and a marker second means a reader can trust "is step N complete"
by checking only for the marker's existence, never observing a partially-uploaded `.pt`.
</details>

<details><summary>4. EKS doesn't auto-taint its spot node group — this chapter's node-group create adds the GPU taint itself. What would go wrong if the <code>eks</code> overlay's TrainJob patch had the <code>nodeSelector</code> but forgot the <code>nvidia.com/gpu</code> toleration?</summary>

The pod would never schedule: it explicitly asks (via `nodeSelector`) for the GPU node group, but
every node in that group carries a `NoSchedule` taint the pod doesn't tolerate, so it sits
`Pending` with a `node(s) had untolerated taint` event forever.
</details>

<details><summary>5. What changes about spot/on-demand placement when you layer <code>kueue/eks</code> instead of applying the plain <code>eks</code> overlay?</summary>

Without Kueue, the `eks` overlay's `nodeSelector` hardcodes spot — if spot capacity is
unavailable the TrainJob just sits `Pending`. With Kueue, the hardcoded capacity-type key is
removed and Kueue's ClusterQueue (spot ResourceFlavor tried first, on-demand as fallback) decides
placement at admission time, writing its own `runtimePatch` with whichever flavor's
selector/toleration it admitted the Workload into.
</details>

<details><summary>6. Why does the runtime set <code>restartPolicy: Never</code> on the pod template instead of relying on Kubernetes' own pod restart?</summary>

A kubelet-level pod restart (`restartPolicy: OnFailure`) would restart *only that container in
place*, re-executing `torchrun` without the other rank's world re-forming — same problem as
question 1. Failing the pod outright (with `backoffLimit: 0` failing the whole Job) lets the
JobSet-level `Recreate` policy own the gang-wide restart instead.
</details>

<details><summary>7. Why is <code>numNodes: 2, numProcPerNode: 1</code> used here instead of, say, 1 node with 2 GPUs?</summary>

The chapter is demonstrating *multi-node* DDP (the JobSet/rendezvous/checkpoint machinery this
chapter is about) on the cheapest possible GPU shape — 1-GPU instances (L4/T4) are widely
available and cheap on spot. Multi-GPU-per-node would use `numProcPerNode > 1` instead/in
addition and doesn't exercise cross-node NCCL at all.
</details>

<details><summary>8. §3.4 removes the hardcoded <code>eks.amazonaws.com/capacityType: SPOT</code> key from the TrainJob's <code>runtimePatches</code> before layering Kueue admission on top. Why is that removal necessary?</summary>

The TrainJob's own `runtimePatches` entry hardcodes spot placement; if it stays in place, the pod's
`nodeSelector` still demands spot capacity regardless of what Kueue decides, so the TrainJob would
sit `Pending` if spot is unavailable even though Kueue's ClusterQueue has an on-demand
ResourceFlavor with real capacity. Removing just that key (keeping the GPU-type selector and
tolerations) leaves Kueue's own admission-time `runtimePatch` free to add back whichever capacity
type it actually admitted the Workload into.
</details>

<details><summary>9. Why does an AdamW training run on a 7B parameter model require ~112 GB VRAM before batch activations, and why does FSDP FULL_SHARD solve this?</summary>

In half-precision (FP16/BF16), model weights take 2 bytes/param (14 GB) and gradients take 2 bytes/param (14 GB).
AdamW maintains an FP32 master weight copy (4 bytes/param) plus first and second momentum vectors (8 bytes/param),
adding 12 bytes/param (84 GB). The total static state is 16 bytes per parameter (112 GB). DDP replicates this
entire 112 GB on every single GPU, causing immediate OOM. FSDP `FULL_SHARD` shards the weights, gradients, and
optimizer states across all participating GPUs (e.g. across 8 GPUs, each holds only 14 GB), gathering layers
on-demand during forward/backward passes and freeing them immediately.
</details>

<details><summary>10. What role does AWS EFA (Elastic Fabric Adapter) and GPUDirect RDMA play in multi-node training, and why is an EC2 cluster placement group necessary?</summary>

Standard cloud networking uses TCP/IP kernel stacks with jitter and latency, bottlenecking NCCL `all-reduce`
gradient exchanges. EFA provides OS-bypass with Libfabric and SRD (Scalable Reliable Datagram) multi-path routing,
while GPUDirect RDMA copies data directly between GPU VRAM across physical hosts without CPU/RAM staging.
An EC2 `cluster` placement group ensures all training instances are placed in the same physical datacenter rack
on the same network switch, eliminating inter-switch latency and achieving full line-rate inter-node bandwidth.
</details>

## 9. Further reading

- [Kubeflow Trainer v2 docs](https://www.kubeflow.org/docs/components/trainer/)
- [Kubeflow Trainer API reference (TrainJob/TrainingRuntime)](https://www.kubeflow.org/docs/components/trainer/reference/)
- [JobSet](https://jobset.sigs.k8s.io/)
- [torchrun / torch.distributed elastic](https://pytorch.org/docs/stable/elastic/run.html)
- [EKS: Mountpoint for Amazon S3 CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/s3-csi.html)
- Cross-links: `05-model-storage-and-data` (the CSI drivers used for checkpoints here),
  `06-batch-jobs-and-kueue` (the `team-research` ClusterQueue the optional `kueue/<cloud>` overlay
  submits into), `08-ray-on-kubernetes` (an alternative gang-scheduled distributed workload model),
  and [AI Infrastructure Research & Articles](../AI_INFRASTRUCTURE_RESEARCH_AND_ARTICLES.md#21-advanced-gpu-interconnect--fabric-networking-rdma-rocev2-efa-nccl) (deep dive into RDMA, AWS EFA, NCCL tuning, ZeRO, and Megatron-LM)

### Versions tested

| Component                | Version                                                                                | Source                                                           |
| ------------------------ | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Kubeflow Trainer         | `${KUBEFLOW_TRAINER_VERSION}` (v2.3.0)                                                 | `versions.env`, `oci://ghcr.io/kubeflow/charts/kubeflow-trainer` |
| PyTorch training image   | `pytorch/pytorch:2.13.0-cuda12.6-cudnn9-runtime` (GPU), `-cuda13.0-` (runtime default) | Docker Hub `pytorch/pytorch`                                     |
| Kueue (optional overlay) | `${KUEUE_VERSION}` (0.19.4)                                                            | `versions.env`, `kueue.x-k8s.io/v1beta2`                         |

---

[← Prev: 06-batch-jobs-and-kueue](../06-batch-jobs-and-kueue) | [Course Map](../README.md) | [Next: 08-ray-on-kubernetes →](../08-ray-on-kubernetes)