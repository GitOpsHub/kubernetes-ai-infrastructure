# Autoscaling inference with KEDA

CPU-based autoscaling doesn't work for GPU inference. A vLLM pod's CPU barely moves while its
GPU is saturated. The course scales on **queue depth** instead: vLLM's Prometheus metric
`vllm:num_requests_waiting` (requests queued that the current batch hasn't started yet).

## HPA vs KEDA

- **HPA v2 + prometheus-adapter**: the adapter exposes a PromQL rule as a custom metric
  (`custom.metrics.k8s.io`) that the HPA polls. It can't scale to zero: `minReplicas` must be
  at least 1.
- **KEDA**: a `ScaledObject` CRD with built-in scalers (`prometheus`, `cpu`, `cron`, many more)
  that query the source directly. Above `minReplicaCount` it creates and manages an HPA for you.
  Below it, including to and from **zero**, KEDA scales the Deployment itself.

The course's ScaledObject for vLLM uses a `prometheus` trigger with the query
`sum(vllm:num_requests_waiting{...})`, `threshold: "5"`, `activationThreshold: "0.5"`,
`minReplicaCount: 0`, `maxReplicaCount: 4`, `cooldownPeriod: 300` and a 300 s scale-down
stabilization window.

## Cold starts are the price of scale-to-zero

Going from 0 to 1 GPU replica isn't like scaling a web pod:

- node provisioning (if the GPU pool is at 0): 1-8 minutes
- image pull (if not cached on the node): 10 s to 2 minutes
- weight load (on a cache miss): 10 s to 2 minutes for a small model
- CUDA graph capture plus KV cache allocation: 10-60 s

Best case is about 30-60 s. Worst case, with a cold node and cold cache, is 5-12 minutes. Use
scale-to-zero for dev and batch-style traffic. Keep `minReplicaCount: 1` for latency-sensitive
APIs, and make the first request's client timeout long enough.

## Pending pods after scale-up

KEDA or the HPA only create pods. If no GPU node has room, the pod stays `Pending` until the node
autoscaler (Karpenter on EKS, NAP on GKE/AKS) provisions one. Check both layers when a scale-out
seems stuck.
