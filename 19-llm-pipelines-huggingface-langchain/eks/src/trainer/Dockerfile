# Chapter 19 trainer image: finetune.py / evaluate.py / publish_hf.py on torch + HF stack.
#
#   GPU (default):  docker buildx build --platform linux/amd64 -t ch19-trainer .
#   CPU lab:        docker buildx build --platform linux/amd64 --build-arg TORCH_VARIANT=cpu -t ch19-trainer:cpu .
#
# torch comes from the PyTorch wheel index for TORCH_VARIANT: cu129 (CUDA 12.9, works on
# the older drivers GPU node images ship, same choice as ch09's -cu129 vLLM image) or cpu.
# The CUDA runtime is inside the torch wheels (nvidia-* packages), so a slim Python base
# is enough; the node only needs the NVIDIA driver (ch01/ch02).
FROM python:3.12-slim-trixie

COPY --from=ghcr.io/astral-sh/uv:0.12.15 /uv /bin/uv

ARG TORCH_VARIANT=cu129
ARG TORCH_VERSION=2.13.0

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HF_HUB_DISABLE_TELEMETRY=1

# 1) torch alone, from the PyTorch index (which also mirrors its dependencies).
RUN uv pip install --system --no-cache "torch==${TORCH_VERSION}" \
      --index-url "https://download.pytorch.org/whl/${TORCH_VARIANT}"

# 2) The HF stack from PyPI. The constraint keeps the torch installed above: the
#    installed 2.13.0+<variant> satisfies ==2.13.0, so uv never replaces it with the
#    PyPI build.
COPY requirements.txt /tmp/requirements.txt
RUN echo "torch==${TORCH_VERSION}" > /tmp/torch-constraint.txt \
 && uv pip install --system --no-cache -r /tmp/requirements.txt -c /tmp/torch-constraint.txt \
 && rm /tmp/requirements.txt /tmp/torch-constraint.txt

WORKDIR /app
COPY *.py /app/

# Runs as root on purpose: the bucket CSI mounts (Mountpoint for S3, GCS FUSE, Blob CSI)
# are only writable by root unless the PV sets uid/gid mount options. Workflow steps
# invoke each script explicitly (python /app/<script>.py); CMD is just a default.
CMD ["python", "/app/finetune.py"]
