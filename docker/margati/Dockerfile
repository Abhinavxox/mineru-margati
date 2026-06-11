# Margati production image — bakes in modified MinerU source; models mounted at runtime.
#
# Base: vLLM 0.21.0 (torch 2.11 + CUDA 13). L4 / Ada Lovelace (CC 8.9) supported.
# For CUDA 12.9 hosts, swap the FROM line to vllm/vllm-openai:v0.21.0-cu129
#
# Build (from repo root):
#   docker build -t margati/mineru-api:latest -f docker/margati/Dockerfile .
#
# Run:
#   docker compose -f docker/margati/docker-compose.yml up -d

# Default to cu129 for broad GPU host compatibility (CUDA 12.8+ drivers, e.g. RunPod L4).
# For CUDA 13.0+ drivers only, switch to vllm/vllm-openai:v0.21.0
FROM vllm/vllm-openai:v0.21.0-cu129
# FROM vllm/vllm-openai:v0.21.0

ENV PYTHONUNBUFFERED=1 \
    MINERU_MODEL_SOURCE=local \
    MINERU_TOOLS_CONFIG_JSON=/etc/mineru/mineru.json \
    MINERU_API_OUTPUT_ROOT=/var/lib/mineru/output

# OpenCV + CJK fonts (same as upstream MinerU image)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        fonts-noto-core \
        fonts-noto-cjk \
        fontconfig \
        libgl1 && \
    fc-cache -fv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mineru

# Copy modified source and install into the image (non-editable; code locked in layer)
COPY pyproject.toml README.md LICENSE.md mineru.template.json ./
COPY mineru ./mineru
RUN python3 -m pip install --no-cache-dir --break-system-packages '.[all]' && \
    python3 -m pip cache purge

# Default config path; override at runtime via volume if needed
RUN mkdir -p /etc/mineru
COPY docker/margati/mineru.json /etc/mineru/mineru.json

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["mineru-api"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--enable-vlm-preload", "true"]
