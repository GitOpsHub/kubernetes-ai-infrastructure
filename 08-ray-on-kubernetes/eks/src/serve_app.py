"""Chapter 08 - Ray Serve app: Qwen3-0.6B text generation on CPU, deployed via RayService.

This is intentionally the *pattern*, not a production inference stack -- Ray Serve's value here is
the deployment graph (replicas, autoscaling, composition, zero-downtime upgrades via RayService),
not raw throughput. For real LLM serving throughput/latency (continuous batching, PagedAttention,
tensor parallel, GPU) see 09-llm-inference-with-vllm; Ray Serve can also front a vLLM deployment
for multi-model composition, which is out of scope for this intro chapter.

HF_TOKEN is not needed: Qwen/Qwen3-0.6B is ungated.
"""

from ray import serve
from starlette.requests import Request


@serve.deployment(
    ray_actor_options={"num_cpus": 2},
    autoscaling_config={"min_replicas": 1, "max_replicas": 2, "target_ongoing_requests": 2},
)
class QwenGenerator:
    def __init__(self) -> None:
        from transformers import pipeline

        self._pipe = pipeline(
            "text-generation",
            model="Qwen/Qwen3-0.6B",
            device=-1,  # CPU
        )

    def generate(self, prompt: str, max_new_tokens: int = 64) -> str:
        out = self._pipe(
            prompt,
            max_new_tokens=max_new_tokens,
            do_sample=False,
        )
        return out[0]["generated_text"]

    async def __call__(self, request: Request) -> dict:
        body = await request.json()
        prompt = body.get("prompt", "Kubernetes is")
        max_new_tokens = int(body.get("max_new_tokens", 64))
        return {"generated_text": self.generate(prompt, max_new_tokens)}


app = QwenGenerator.bind()
