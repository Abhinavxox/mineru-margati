#!/usr/bin/env bash
# Run production-equivalent stack without Docker (for dev pods / smoke testing).
# Starts mineru-api with VLM preload, then optionally tests with test.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
API_PORT="${API_PORT:-8000}"
ROUTER_PORT="${ROUTER_PORT:-8002}"
MODELS_DIR="${MINERU_MODELS_DIR:-/workspace/mineru_models}"
CONFIG_FILE="${MINERU_CONFIG_FILE:-/workspace/mineru.json}"
OUTPUT_ROOT="${MINERU_API_OUTPUT_ROOT:-/workspace/mineru_output}"
PDF_PATH="${1:-/workspace/test_cases/test.pdf}"

mkdir -p "$OUTPUT_ROOT"

# RunPod L4 ships CUDA 12.8 drivers; align runtime libs for torch cu128 + vllm.
export LD_LIBRARY_PATH="/usr/local/lib/python3.11/dist-packages/nvidia/cu13/lib:/usr/local/lib/python3.11/dist-packages/nvidia/cuda_runtime/lib:/usr/local/cuda-12.4/targets/x86_64-linux/lib:${LD_LIBRARY_PATH:-}"

export MINERU_MODEL_SOURCE=local
export MINERU_TOOLS_CONFIG_JSON="$CONFIG_FILE"
export MINERU_API_OUTPUT_ROOT="$OUTPUT_ROOT"
export MINERU_API_MAX_CONCURRENT_REQUESTS="${MINERU_API_MAX_CONCURRENT_REQUESTS:-2}"

API_PID=""
ROUTER_PID=""
cleanup() {
  [[ -n "$ROUTER_PID" ]] && kill "$ROUTER_PID" 2>/dev/null || true
  [[ -n "$API_PID" ]] && kill "$API_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Starting mineru-api on :$API_PORT (VLM preload)..."
mineru-api \
  --host 0.0.0.0 \
  --port "$API_PORT" \
  --enable-vlm-preload true \
  > /tmp/margati-mineru-api.log 2>&1 &
API_PID=$!

echo "==> Waiting for mineru-api health..."
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${API_PORT}/health" | grep -q '"status": "healthy"'; then
    echo "mineru-api healthy"
    break
  fi
  if ! kill -0 "$API_PID" 2>/dev/null; then
    echo "mineru-api exited early:" >&2
    tail -50 /tmp/margati-mineru-api.log >&2 || true
    exit 1
  fi
  sleep 5
done

echo "==> Starting mineru-router on :$ROUTER_PORT..."
mineru-router \
  --host 0.0.0.0 \
  --port "$ROUTER_PORT" \
  --local-gpus none \
  --upstream-url "http://127.0.0.1:${API_PORT}" \
  > /tmp/margati-mineru-router.log 2>&1 &
ROUTER_PID=$!

echo "==> Waiting for mineru-router health..."
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${ROUTER_PORT}/health" | grep -q '"status": "healthy"'; then
    echo "mineru-router healthy"
    break
  fi
  sleep 2
done

if [[ -f "$PDF_PATH" ]]; then
  echo "==> Running smoke test through router..."
  "$ROOT/docker/margati/test.sh" "$PDF_PATH" "http://127.0.0.1:${ROUTER_PORT}"
else
  echo "No PDF at $PDF_PATH — services left running until script exits."
  sleep infinity
fi
