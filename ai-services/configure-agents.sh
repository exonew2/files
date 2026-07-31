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
MCP_SERVER_PY="$PROJECT_ROOT/.opencode/mcp-server/server.py"
NB_NOTEBOOKS="${NOTEBOOKLM_NOTEBOOKS:-18deba09-f237-4348-9ad8-68f4f6f859f7}"
NB_CACHE_DIR="${NOTEBOOKLM_CACHE_DIR:-$HOME/.ash/notebooklm/cache}"

# ── Shared MCP server block (used in all configs) ─────────────────────────────
# Three servers registered everywhere:
#   notebooklm  → npx notebooklm-mcp-server server  (real Google NotebookLM)
#   ash-project → python3 .opencode/mcp-server/server.py (4,587 files indexed)
#   codebase-memory → codebase-memory-mcp (SQLite knowledge graph)

_mcp_servers_json() {
  python3 - "$MCP_SERVER_PY" "$DB_PATH" "$PROJECT_ROOT" "$NB_NOTEBOOKS" "$NB_CACHE_DIR" << 'PY'
import json, sys
mcp_py, db, root, notebooks, cache = sys.argv[1:]
servers = {
    "notebooklm": {
        "command": "npx",
        "args": ["notebooklm-mcp-server", "server"],
        "env": {}
    },
    "ash-project": {
        "command": "python3",
        "args": [mcp_py],
        "env": {
            "ASH_PROJECT_ROOT": root,
            "NOTEBOOKLM_NOTEBOOKS": notebooks,
            "NOTEBOOKLM_CACHE_DIR": cache
        }
    },
    "codebase-memory": {
        "command": "codebase-memory-mcp",
        "args": [],
        "env": {"CBM_MEMORY_PATH": db}
    }
}
print(json.dumps(servers, indent=4))
PY
}

# ── Merge helper: upsert mcpServers into any config file ─────────────────────
_merge_mcp_into() {
  local config_file="$1"
  local key="${2:-mcpServers}"   # Claude/Cursor/Windsurf use mcpServers; Cline uses root
  local servers_json
  servers_json=$(_mcp_servers_json)

  if [[ -f "$config_file" ]]; then
    local tmp
    tmp=$(mktemp)
    python3 - "$config_file" "$tmp" "$key" "$servers_json" << 'PY'
import json, sys
cfg_path, tmp_path, key, servers_raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
new_servers = json.loads(servers_raw)
try:
    with open(cfg_path) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
if key and key != "root":
    cfg.setdefault(key, {}).update(new_servers)
else:
    cfg.update(new_servers)
with open(tmp_path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
    cp "$tmp" "$config_file"
    rm -f "$tmp"
    echo "  [merge] $config_file"
    return 0
  else
    mkdir -p "$(dirname "$config_file")"
    python3 - "$config_file" "$servers_json" << 'PY'
import json, sys
cfg_path, servers_raw = sys.argv[1], sys.argv[2]
with open(cfg_path, "w") as f:
    json.dump({"mcpServers": json.loads(servers_raw)}, f, indent=2)
PY
    echo "  [create] $config_file"
    return 0
  fi
}

# ── 1. Claude Desktop ─────────────────────────────────────────────────────────
configure_claude() {
  local os_type config_dir
  os_type="$(uname -s)"
  case "$os_type" in
    Darwin) config_dir="$HOME/Library/Application Support/Claude" ;;
    Linux)  config_dir="$HOME/.config/Claude" ;;
    *)      echo "  [skip] Claude Desktop: unsupported OS ($os_type)"; SKIPPED+=("Claude"); return ;;
  esac

  local config_file="$config_dir/claude_desktop_config.json"
  if _merge_mcp_into "$config_file" "mcpServers"; then
    GENERATED+=("Claude Desktop ($([ -f "$config_file.bak" ] && echo merged || echo created))")
  else
    FAILED+=("Claude Desktop")
  fi
}

# ── 2. Cursor ─────────────────────────────────────────────────────────────────
configure_cursor() {
  # .cursorrules
  local rules_file="$PROJECT_ROOT/.cursorrules"
  if [[ -f "$rules_file" ]] && grep -q "ash-project\|notebooklm" "$rules_file" 2>/dev/null; then
    echo "  [skip] .cursorrules already configured"
    SKIPPED+=(".cursorrules")
  else
    {
      [[ -f "$rules_file" ]] && cat "$rules_file"
      echo ""
      echo "# Ash MCP servers: notebooklm (npx notebooklm-mcp-server) + ash-project ($MCP_SERVER_PY)"
      echo "# DB: $DB_PATH | Vectors: $VECTORS_PATH"
      [[ -f "$PONYTAIL_RULES" ]] && cat "$PONYTAIL_RULES"
    } > "$rules_file.tmp" && mv "$rules_file.tmp" "$rules_file"
    echo "  [write] .cursorrules"
    GENERATED+=(".cursorrules")
  fi

  # .cursor/mcp.json — use npx directly (not shim)
  local cursor_mcp="$PROJECT_ROOT/.cursor/mcp.json"
  mkdir -p "$PROJECT_ROOT/.cursor"
  if _merge_mcp_into "$cursor_mcp" "mcpServers"; then
    GENERATED+=("Cursor MCP ($cursor_mcp)")
  else
    FAILED+=("Cursor MCP")
  fi
}

# ── 3. Windsurf ───────────────────────────────────────────────────────────────
configure_windsurf() {
  # .windsurfrules
  local rules_file="$PROJECT_ROOT/.windsurfrules"
  if [[ -f "$rules_file" ]] && grep -q "ash-project\|notebooklm" "$rules_file" 2>/dev/null; then
    echo "  [skip] .windsurfrules already configured"
    SKIPPED+=(".windsurfrules")
  else
    {
      [[ -f "$rules_file" ]] && cat "$rules_file"
      echo ""
      echo "# Ash MCP: notebooklm + ash-project ($MCP_SERVER_PY)"
      [[ -f "$PONYTAIL_RULES" ]] && cat "$PONYTAIL_RULES"
    } > "$rules_file.tmp" && mv "$rules_file.tmp" "$rules_file"
    echo "  [write] .windsurfrules"
    GENERATED+=(".windsurfrules")
  fi

  local ws_mcp="$PROJECT_ROOT/.windsurf/mcp.json"
  mkdir -p "$PROJECT_ROOT/.windsurf"
  if _merge_mcp_into "$ws_mcp" "mcpServers"; then
    GENERATED+=("Windsurf MCP ($ws_mcp)")
  else
    FAILED+=("Windsurf MCP")
  fi
}

# ── 4. Cline (VSCode) ─────────────────────────────────────────────────────────
configure_cline() {
  local cline_file="$PROJECT_ROOT/.vscode/cline_mcp.json"
  mkdir -p "$PROJECT_ROOT/.vscode"
  # Cline uses root-level keys (no mcpServers wrapper)
  if _merge_mcp_into "$cline_file" "root"; then
    GENERATED+=("Cline MCP ($cline_file)")
  else
    FAILED+=("Cline MCP")
  fi
}

# ── 5. OpenCode ───────────────────────────────────────────────────────────────
configure_opencode() {
  local opencode_cfg="$PROJECT_ROOT/.opencode/config.json"
  mkdir -p "$PROJECT_ROOT/.opencode"

  local servers_json
  servers_json=$(_mcp_servers_json)

  if [[ -f "$opencode_cfg" ]]; then
    local tmp
    tmp=$(mktemp)
    python3 - "$opencode_cfg" "$tmp" "$servers_json" << 'PY'
import json, sys
cfg_path, tmp_path, servers_raw = sys.argv[1], sys.argv[2], sys.argv[3]
new_servers = json.loads(servers_raw)
try:
    with open(cfg_path) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
# OpenCode uses "mcp" key with same format as mcpServers
cfg.setdefault("mcp", {}).update(new_servers)
# Also keep legacy mcpServers for compatibility
cfg.setdefault("mcpServers", {}).update(new_servers)
with open(tmp_path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
    cp "$tmp" "$opencode_cfg"
    rm -f "$tmp"
    echo "  [merge] $opencode_cfg"
    GENERATED+=("OpenCode config (merged)")
  else
    python3 - "$opencode_cfg" "$servers_json" << 'PY'
import json, sys
cfg_path, servers_raw = sys.argv[1], sys.argv[2]
servers = json.loads(servers_raw)
with open(cfg_path, "w") as f:
    json.dump({"mcp": servers, "mcpServers": servers}, f, indent=2)
PY
    echo "  [create] $opencode_cfg"
    GENERATED+=("OpenCode config (created)")
  fi
}

# ── 6. Generic Gemini Context ─────────────────────────────────────────────────
configure_generic() {
  local gemini_file="$SELF_DIR/gemini-context.json"
  python3 - "$gemini_file" "$DB_PATH" "$VECTORS_PATH" "$SELF_DIR" "$MCP_SERVER_PY" "$NB_NOTEBOOKS" << 'PY'
import json, sys
out_path, db, vectors, self_dir, mcp_py, notebooks = sys.argv[1:]
cfg = {
    "system_instructions": (
        "You have access to a codebase memory system, Qdrant vector DB, "
        "NotebookLM notebook knowledge, and 4,587 indexed project files. "
        "Use them for persistent context across sessions."
    ),
    "mcp_servers": {
        "notebooklm": {
            "command": "npx",
            "args": ["notebooklm-mcp-server", "server"],
            "description": "Google NotebookLM — architecture decisions, research notes"
        },
        "ash-project": {
            "command": "python3",
            "args": [mcp_py],
            "env": {"ASH_PROJECT_ROOT": str(__import__('pathlib').Path(mcp_py).parent.parent),
                    "NOTEBOOKLM_NOTEBOOKS": notebooks},
            "description": "Local ash-iso project index (4,587 files, search_project/get_context)"
        },
        "codebase-memory": {
            "command": "codebase-memory-mcp",
            "args": [],
            "env": {"CBM_MEMORY_PATH": db},
            "description": "SQLite knowledge graph with graph nodes/edges"
        }
    },
    "endpoints": {
        "codebase_memory": {"type": "mcp", "server": "codebase-memory-mcp"},
        "database": {"type": "sqlite", "path": db},
        "vectors": {"type": "chromadb", "path": vectors}
    },
    "tools_dir": f"{self_dir}/tools"
}
with open(out_path, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"  [write] {out_path}")
PY
  GENERATED+=("Gemini context")
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo "=== Ash Agent Configuration Generator ==="
echo "Project root:  $PROJECT_ROOT"
echo "AI Services:   $SELF_DIR"
echo "NotebookLM ID: $NB_NOTEBOOKS"
echo "MCP server:    $MCP_SERVER_PY"
echo ""

echo "[1/6] Claude Desktop..."
configure_claude

echo "[2/6] Cursor..."
configure_cursor

echo "[3/6] Windsurf..."
configure_windsurf

echo "[4/6] Cline (VSCode)..."
configure_cline

echo "[5/6] OpenCode..."
configure_opencode

echo "[6/6] Gemini context..."
configure_generic

echo ""
echo "=== Summary ==="
echo "Generated/updated: ${#GENERATED[@]}"
for g in "${GENERATED[@]}"; do echo "  + $g"; done
echo "Skipped: ${#SKIPPED[@]}"
for s in "${SKIPPED[@]}"; do echo "  - $s"; done
echo "Failed: ${#FAILED[@]}"
for f in "${FAILED[@]}"; do echo "  ! $f"; done
echo ""
echo "All 3 MCP servers configured: notebooklm + ash-project + codebase-memory"
echo "Run any agent tool and use: @notebooklm, @ash-project, or @codebase-memory"
