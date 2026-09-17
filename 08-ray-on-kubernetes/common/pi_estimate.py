"""Chapter 08 - toy RayJob entrypoint: embarrassingly-parallel Monte Carlo pi estimate.

Run by `python /home/ray/samples/pi_estimate.py` as the RayJob's entrypoint. It's deliberately
CPU-only and tiny so the lab is cheap and fast to run through Kueue -- the point of this manifest
is the RayJob lifecycle (ephemeral cluster spun up for the job, torn down after), not the
workload. Swap in a real training/batch-inference entrypoint once you're comfortable with the
mechanics; 07-distributed-training-kubeflow-trainer covers gang-scheduled multi-node PyTorch DDP
for that case, and 09-llm-inference-with-vllm covers real LLM serving.
"""

import os
import time

import ray


@ray.remote
def samples_in_circle(n: int, seed: int) -> int:
    import random

    rng = random.Random(seed)
    hits = 0
    for _ in range(n):
        x, y = rng.random(), rng.random()
        if x * x + y * y <= 1.0:
            hits += 1
    return hits


def main() -> None:
    ray.init(address="auto")

    num_tasks = int(os.environ.get("NUM_TASKS", "16"))
    samples_per_task = int(os.environ.get("SAMPLES_PER_TASK", "2_000_000"))

    print(f"[pi_estimate] {num_tasks} tasks x {samples_per_task} samples, cluster resources:")
    print(ray.cluster_resources())

    start = time.time()
    futures = [samples_in_circle.remote(samples_per_task, seed) for seed in range(num_tasks)]
    hits = sum(ray.get(futures))
    elapsed = time.time() - start

    total = num_tasks * samples_per_task
    pi_estimate = 4.0 * hits / total
    print(f"[pi_estimate] pi ~= {pi_estimate:.6f} (total_samples={total}, elapsed={elapsed:.1f}s)")

    ray.shutdown()


if __name__ == "__main__":
    main()
