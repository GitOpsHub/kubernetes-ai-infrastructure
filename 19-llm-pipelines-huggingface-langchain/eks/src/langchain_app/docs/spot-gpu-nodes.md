# Spot GPU nodes on this platform

Every GPU in this course runs on **spot capacity** by default, with on-demand as the documented
fallback. Spot is much cheaper, but the cloud can reclaim a node with very little notice. So
every GPU workload here has to tolerate a restart.

## How a pod lands on a GPU node

A pod needs three things before the scheduler will place it on a spot GPU node:

1. **A GPU request**: `resources.limits: nvidia.com/gpu: 1`. The NVIDIA device plugin advertises
   this extended resource on the node.
2. **A toleration for the GPU taint** `nvidia.com/gpu=present:NoSchedule`. GKE adds this taint
   to GPU pools automatically. On EKS the `spot-gpu` node group sets it explicitly.
3. **A node selector** for the right capacity type:
   - GKE: `cloud.google.com/gke-spot: "true"`
   - EKS: `eks.amazonaws.com/capacityType: SPOT`, plus `nvidia.com/gpu.present: "true"`
   - AKS: `kubernetes.azure.com/scalesetpriority: spot`

**AKS is the odd one out.** Every AKS spot pool is auto-tainted with
`kubernetes.azure.com/scalesetpriority=spot:NoSchedule`, so AKS pods also need a toleration for
that taint. GKE and EKS don't add a spot taint. Forget the toleration and the pod
stays `Pending` without any obvious error.

## Keeping cost at zero when idle

GPU node pools are created with **min nodes = 0**. They only cost money while a GPU pod is
pending or running. On EKS the `spot-gpu` node group uses `g4dn.xlarge` instances.
The default lab keeps it to a single cheap GPU class so idle cost stays low and the node group stays easy to reason about.
per availability zone, so more eligible shapes means fewer stockouts.

## Surviving a reclaim

- Keep `terminationGracePeriodSeconds` below the tightest spot notice window you run on
  (GKE ~15 s for regular pods, AKS ~30 s, EC2 ~2 min).
- Training must checkpoint to durable storage and resume from the last *complete* checkpoint.
- Batch pipelines should retry the failed step (for example an Argo `retryStrategy`) instead of
  rerunning the whole pipeline.
- T4 GPUs (`g4dn`) have no bf16 support, so training falls back to fp16 there.
