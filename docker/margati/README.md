# Margati MinerU Production Image

Production Docker setup for deploying modified MinerU source as `mineru-api` workers.
Model weights stay **outside** the image and are mounted at runtime.

## What this image contains

- Modified MinerU source from this repository (installed with `pip install '.[all]'`, not editable)
- vLLM 0.21.0 + torch 2.11 (CUDA 13) from `vllm/vllm-openai:v0.21.0`
- Default config at `/etc/mineru/mineru.json` pointing to `/models/MinerU2.5-Pro-2604-1.2B`

## What stays external (mounted)

- VLM weights: host `MINERU_MODELS_DIR` → container `/models`
- Optional config override: host `MINERU_CONFIG_FILE` → `/etc/mineru/mineru.json`

## Build

From the MinerU repository root:

```bash
docker build -t margati/mineru-api:latest -f docker/margati/Dockerfile .
```

## Run with Docker Compose

```bash
cd docker/margati

# Default: models at /workspace/mineru_models (RunPod volume layout)
docker compose up -d --build

# Custom model path
MINERU_MODELS_DIR=/data/mineru_models docker compose up -d
```

API docs: `http://<host>:8000/docs`

## Run with docker run

```bash
docker run -d --name margati-mineru-api \
  --gpus '"device=0"' \
  --ipc=host \
  --shm-size=16g \
  -p 8000:8000 \
  -e MINERU_MODEL_SOURCE=local \
  -e MINERU_TOOLS_CONFIG_JSON=/etc/mineru/mineru.json \
  -v /workspace/mineru_models:/models:ro \
  -v "$(pwd)/docker/margati/mineru.json:/etc/mineru/mineru.json:ro" \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  margati/mineru-api:latest
```

## Multi-worker deployment (Margati)

Run one container per GPU worker node. Each node:

1. Pulls the same `margati/mineru-api` image (or builds from the same commit)
2. Mounts the same model directory (shared NFS, RunPod network volume, or pre-synced copy)
3. Exposes port `8000` behind your load balancer / router

To aggregate workers with MinerU Router instead of hitting each API directly:

```bash
mineru-router --host 0.0.0.0 --port 8002 \
  --local-gpus none \
  --upstream-url http://worker-1:8000 \
  --upstream-url http://worker-2:8000
```

## CUDA 12.9 hosts

Edit `Dockerfile` and switch the `FROM` line to `vllm/vllm-openai:v0.21.0-cu129`.
