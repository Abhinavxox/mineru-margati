#!/usr/bin/env bash
# Smoke test for Margati MinerU HA stack.
# Usage: ./test.sh [pdf_path] [base_url]
set -euo pipefail

PDF_PATH="${1:-/workspace/test_cases/test.pdf}"
BASE_URL="${2:-http://127.0.0.1:8000}"
OUT_DIR="${TMPDIR:-/tmp}/margati-mineru-test-$$"
MAX_WAIT="${MAX_WAIT:-600}"

if [[ ! -f "$PDF_PATH" ]]; then
  echo "ERROR: PDF not found: $PDF_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
trap 'rm -rf "$OUT_DIR"' EXIT

echo "==> Health check: $BASE_URL/health"
deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  if curl -fsS "$BASE_URL/health" -o "$OUT_DIR/health.json"; then
    if grep -q '"status": "healthy"' "$OUT_DIR/health.json"; then
      cat "$OUT_DIR/health.json"
      break
    fi
  fi
  sleep 2
done

if ! grep -q '"status": "healthy"' "$OUT_DIR/health.json" 2>/dev/null; then
  echo "ERROR: Service not healthy after 30s" >&2
  cat "$OUT_DIR/health.json" 2>/dev/null || true
  exit 1
fi

echo
echo "==> Submit async task: $PDF_PATH"
TASK_RESPONSE="$(
  curl -fsS -X POST "$BASE_URL/tasks" \
    -F "files=@${PDF_PATH}" \
    -F "return_md=true"
)"
echo "$TASK_RESPONSE" | tee "$OUT_DIR/task.json"

TASK_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])' <<<"$TASK_RESPONSE")"
echo "Task ID: $TASK_ID"

echo
echo "==> Poll task status (timeout ${MAX_WAIT}s)"
deadline=$((SECONDS + MAX_WAIT))
while (( SECONDS < deadline )); do
  STATUS_JSON="$(curl -fsS "$BASE_URL/tasks/$TASK_ID")"
  STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$STATUS_JSON")"
  echo "[$(date +%H:%M:%S)] status=$STATUS"
  case "$STATUS" in
    completed)
      break
      ;;
    failed)
      echo "$STATUS_JSON"
      echo "ERROR: Task failed" >&2
      exit 1
      ;;
  esac
  sleep 3
done

if [[ "$STATUS" != "completed" ]]; then
  echo "ERROR: Task did not complete within ${MAX_WAIT}s" >&2
  exit 1
fi

echo
echo "==> Fetch result"
curl -fsS "$BASE_URL/tasks/$TASK_ID/result" -o "$OUT_DIR/result.zip"
unzip -l "$OUT_DIR/result.zip" | head -20

echo
echo "PASS: Parsed $(basename "$PDF_PATH") successfully via $BASE_URL"
