#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SELF_DIR/.venv"

echo "=== Initializing databases ==="
"$VENV/bin/python3" "$SELF_DIR/init_db.py"

echo ""
echo "=== Starting codebase-memory MCP server ==="
codebase-memory-mcp
