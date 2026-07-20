#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$SELF_DIR/.venv"

start_codebase_memory() {
  echo "Starting codebase-memory-mcp MCP server..."
  codebase-memory-mcp
}

start_notebooklm() {
  echo "Starting NotebookLM CLI..."
  "$VENV/bin/notebooklm" "$@"
}

start_textgrad() {
  echo "Starting TextGrad..."
  "$VENV/bin/python3" -c "
from textgrad import Variable, Engine
print('TextGrad imported successfully')
"
}

start_prompt_optimizer() {
  echo "Starting Prompt Optimizer..."
  cd "$SELF_DIR/tools/prompt-optimizer"
  if [ -f "package.json" ]; then
    npm start
  else
    echo "No start script found"
  fi
}

show_help() {
  echo "Usage: $0 <service> [args...]"
  echo ""
  echo "Services:"
  echo "  codebase-memory    Start the codebase-memory MCP server"
  echo "  notebooklm         Run NotebookLM CLI (pass args after)"
  echo "  textgrad           Verify TextGrad installation"
  echo "  prompt-optimizer   Start prompt optimizer"
  echo "  list               List all installed tools"
  echo "  help               Show this help"
}

list_tools() {
  echo "Installed tools in $SELF_DIR/tools:"
  for d in "$SELF_DIR"/tools/*/; do
    name=$(basename "$d")
    echo "  - $name"
  done
  for f in "$SELF_DIR"/tools/*.md; do
    name=$(basename "$f" .md)
    echo "  - $name (skill)"
  done
  echo ""
  echo "Python packages in venv:"
  "$VENV/bin/pip" list 2>/dev/null | grep -E 'notebooklm|textgrad' || echo "  (none)"
}

case "${1:-help}" in
  codebase-memory) shift; start_codebase_memory "$@" ;;
  notebooklm) shift; start_notebooklm "$@" ;;
  textgrad) shift; start_textgrad "$@" ;;
  prompt-optimizer) shift; start_prompt_optimizer "$@" ;;
  list) list_tools ;;
  help|*) show_help ;;
esac
