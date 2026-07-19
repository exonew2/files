#!/usr/bin/env bash
# /usr/lib/iso/ollama-prepull.sh — Pre-pull phi3:mini if not baked in

set -euo pipefail

MODEL_DIR="/usr/share/ollama/.ollama/models"
MANIFEST_DIR="$MODEL_DIR/manifests/registry.ollama.ai/library"

if [[ ! -f "$MANIFEST_DIR/phi3/mini/latest" ]]; then
    mkdir -p "$MODEL_DIR"
    ollama serve &
    OLLAMA_PID=$!
    sleep 3
    ollama pull phi3:mini 2>&1 | logger -t ollama-prepull || true
    kill $OLLAMA_PID 2>/dev/null || true
fi