# Serving LLMs with vLLM

The platform serves models with **vLLM**, which exposes an **OpenAI-compatible API**
(`/v1/models`, `/v1/chat/completions`) on port 8000. Any OpenAI client (the `openai` SDK,
LangChain's `ChatOpenAI`) can talk to it by changing `base_url`. The CPU lab uses Ollama, which
speaks the same OpenAI-style contract, on port 11434.

## Why the probes look unusual

- **startupProbe**: `/health` with `failureThreshold: 60` x `periodSeconds: 10`, a 10-minute
  budget. Downloading weights, capturing CUDA graphs and allocating the KV cache can take
  minutes. Liveness and readiness are suppressed until the startup probe passes, so a slow boot
  isn't killed as unhealthy.
- **readinessProbe**: `/health` on a short interval. The pod only gets traffic once the engine
  can serve.
- **terminationGracePeriodSeconds: 25** with `--shutdown-timeout=10` and a short `preStop`
  sleep, sized to fit inside the tightest spot notice window.

## GPU memory and the KV cache

vLLM pre-allocates most of the GPU's free memory at startup. `--gpu-memory-utilization=0.90`
reserves ~90% for weights, activations and a paged **KV cache** pool. That memory shows as used
even when idle: it is capacity for concurrent sequences, not a leak. If startup fails with
`CUDA out of memory`, lower it to 0.80-0.85. If the model plus `--max-model-len` doesn't fit,
reduce `--max-model-len` (the course uses 8192) or `--max-num-seqs`.

## Deployment shape

A single-GPU vLLM Deployment uses `strategy: Recreate`, not RollingUpdate. A rolling update
would need a second GPU while the old pod is still running. With `replicas: 1`, a spot reclaim
is a real outage until a new node and pod are up.

`--served-model-name` sets the name clients pass as `model`. This decouples clients from the
weights' path, so you can swap in a fine-tuned model without changing callers.

## Qwen3 thinking mode

Qwen3 models emit a `<think>...</think>` reasoning block by default. With vLLM, pass
`chat_template_kwargs: {"enable_thinking": false}` in the request body to switch it off for
short, direct answers.
