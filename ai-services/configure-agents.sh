#!/usr/bin/env bash
set -eo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SELF_DIR/.." && pwd)"
GENERATED=()
SKIPPED=()
FAILED=()

abspath() { echo "$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"; }

DB_PATH="$(abspath "$SELF_DIR/data/memory.db")"
VECTORS_PATH="$(abspath "$SELF_DIR/data/vectors")"
PONYTAIL_RULES="$PROJECT_ROOT/.opencode/ponytail-rules.md"

# ── 1. Claude Desktop ─────────────────────────────────────────
configure_claude() {
  local os_type
  os_type="$(uname -s)"
  local config_dir
  case "$os_type" in
    Darwin) config_dir="$HOME/Library/Application Support/Claude" ;;
    Linux)  config_dir="$HOME/.config/Claude" ;;
    *)      config_dir="" ;;
  esac

  if [ -z "$config_dir" ]; then
    echo "  [skip] Claude Desktop: unsupported OS ($os_type)"
    SKIPPED+=("Claude Desktop (unsupported OS)")
    return
  fi

  mkdir -p "$config_dir"
  local config_file="$config_dir/claude_desktop_config.json"

  local mcp_entry
  mcp_entry=$(cat <<JSON
    "codebase-memory": {
      "command": "codebase-memory-mcp",
      "args": [],
      "env": {
        "CBM_MEMORY_PATH": "$DB_PATH"
      }
    }
JSON
)

  if [ -f "$config_file" ]; then
    local tmp
    tmp=$(mktemp)
    if python3 -c "
import json, sys
with open('$config_file') as f:
    cfg = json.load(f)
if 'mcpServers' not in cfg:
    cfg['mcpServers'] = {}
cfg['mcpServers']['codebase-memory'] = {
    'command': 'codebase-memory-mcp',
    'args': [],
    'env': {'CBM_MEMORY_PATH': '$DB_PATH'}
}
with open('$tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null; then
      cp "$tmp" "$config_file"
      echo "  [merge] Claude Desktop config merged ($config_file)"
      GENERATED+=("Claude Desktop (merged)")
    else
      echo "  [fail] Claude Desktop: merge failed"
      FAILED+=("Claude Desktop (merge failed)")
    fi
    rm -f "$tmp"
  else
    cat > "$config_file" <<JSON
{
  "mcpServers": {
    $mcp_entry
  }
}
JSON
    echo "  [create] Claude Desktop config created ($config_file)"
    GENERATED+=("Claude Desktop (created)")
  fi
}

# ── 2. Cursor ─────────────────────────────────────────────────
configure_cursor() {
  local rules_file="$PROJECT_ROOT/.cursorrules"
  if [ -f "$rules_file" ]; then
    if grep -q "ponytail" "$rules_file" 2>/dev/null; then
      echo "  [skip] .cursorrules already has ponytail rules"
      SKIPPED+=(".cursorrules (already configured)")
      return
    fi
    echo "" >> "$rules_file"
    echo "---" >> "$rules_file"
    echo "// ponytail rules — imported from $PONYTAIL_RULES" >> "$rules_file"
    echo "// DB path: $DB_PATH" >> "$rules_file"
    echo "// Vectors: $VECTORS_PATH" >> "$rules_file"
    echo "  [merge] .cursorrules updated"
    GENERATED+=(".cursorrules (merged)")
  else
    cat > "$rules_file" <<RULES
# Cursor Rules
# DB: $DB_PATH
# Vectors: $VECTORS_PATH

RULES
    cat "$PONYTAIL_RULES" >> "$rules_file" 2>/dev/null || true
    echo "  [create] .cursorrules created"
    GENERATED+=(".cursorrules (created)")
  fi
}

# ── 3. Windsurf ───────────────────────────────────────────────
configure_windsurf() {
  local rules_file="$PROJECT_ROOT/.windsurfrules"
  if [ -f "$rules_file" ]; then
    if grep -q "ponytail" "$rules_file" 2>/dev/null; then
      echo "  [skip] .windsurfrules already has ponytail rules"
      SKIPPED+=(".windsurfrules (already configured)")
      return
    fi
    echo "" >> "$rules_file"
    echo "---" >> "$rules_file"
    echo "# ponytail rules — imported from $PONYTAIL_RULES" >> "$rules_file"
    echo "# DB path: $DB_PATH" >> "$rules_file"
    echo "  [merge] .windsurfrules updated"
    GENERATED+=(".windsurfrules (merged)")
  else
    cat > "$rules_file" <<RULES
# Windsurf Rules
# DB: $DB_PATH
# Vectors: $VECTORS_PATH

RULES
    cat "$PONYTAIL_RULES" >> "$rules_file" 2>/dev/null || true
    echo "  [create] .windsurfrules created"
    GENERATED+=(".windsurfrules (created)")
  fi
}

# ── 4. Cline ──────────────────────────────────────────────────
configure_cline() {
  local vscode_dir="$PROJECT_ROOT/.vscode"
  mkdir -p "$vscode_dir"
  local cline_file="$vscode_dir/cline_mcp.json"

  local entry
  entry=$(cat <<JSON
{
  "codebase-memory": {
    "command": "codebase-memory-mcp",
    "args": [],
    "env": {
      "CBM_MEMORY_PATH": "$DB_PATH"
    }
  },
  "db-endpoint": {
    "command": "python3",
    "args": ["$SELF_DIR/init_db.py"],
    "env": {}
  }
}
JSON
)

  if [ -f "$cline_file" ]; then
    local tmp
    tmp=$(mktemp)
    if python3 -c "
import json, sys
with open('$cline_file') as f:
    cfg = json.load(f)
cfg['codebase-memory'] = {
    'command': 'codebase-memory-mcp',
    'args': [],
    'env': {'CBM_MEMORY_PATH': '$DB_PATH'}
}
cfg['db-endpoint'] = {
    'command': 'python3',
    'args': ['$SELF_DIR/init_db.py'],
    'env': {}
}
with open('$tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null; then
      cp "$tmp" "$cline_file"
      echo "  [merge] Cline MCP config merged ($cline_file)"
      GENERATED+=("Cline MCP (merged)")
    else
      echo "  [fail] Cline: merge failed"
      FAILED+=("Cline MCP (merge failed)")
    fi
    rm -f "$tmp"
  else
    echo "$entry" > "$cline_file"
    echo "  [create] Cline MCP config created ($cline_file)"
    GENERATED+=("Cline MCP (created)")
  fi
}

# ── 5. Generic Gemini Context ─────────────────────────────────
configure_generic() {
  local gemini_file="$SELF_DIR/gemini-context.json"
  if [ ! -f "$gemini_file" ]; then
    cat > "$gemini_file" <<JSON
{
  "system_instructions": "You have access to a codebase memory system and databases. Use them for persistent context across sessions.",
  "endpoints": {
    "codebase_memory": {
      "type": "mcp",
      "server": "codebase-memory-mcp",
      "description": "Codebase knowledge graph for semantic search and entity resolution"
    },
    "database": {
      "type": "sqlite",
      "path": "$DB_PATH",
      "description": "Prompt storage and graph node/edge persistence"
    },
    "vectors": {
      "type": "chromadb",
      "path": "$VECTORS_PATH",
      "description": "Vector embeddings storage"
    }
  },
  "tools": {
    "$SELF_DIR/tools"
  }
}
JSON
    echo "  [create] Gemini context created ($gemini_file)"
    GENERATED+=("Gemini context (created)")
  else
    echo "  [skip] Gemini context already exists"
    SKIPPED+=("Gemini context (already exists)")
  fi
}

# ── Main ──────────────────────────────────────────────────────
echo "=== Agent Configuration Generator ==="
echo "Project root: $PROJECT_ROOT"
echo "AI Services:  $SELF_DIR"
echo ""

echo "[1/5] Claude Desktop..."
configure_claude

echo "[2/5] Cursor..."
configure_cursor

echo "[3/5] Windsurf..."
configure_windsurf

echo "[4/5] Cline..."
configure_cline

echo "[5/5] Generic (Gemini)..."
configure_generic

echo ""
echo "=== Summary ==="
echo "Generated: ${#GENERATED[@]}"
for g in "${GENERATED[@]}"; do echo "  + $g"; done
echo "Skipped: ${#SKIPPED[@]}"
for s in "${SKIPPED[@]}"; do echo "  - $s"; done
echo "Failed: ${#FAILED[@]}"
for f in "${FAILED[@]}"; do echo "  ! $f"; done
