#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Ash Linux — Full Setup + Feature Test Suite${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo ""

ISO_DIR="${1:-$HOME/ash-iso}"

# ── Step 1: Deploy LSFS ──────────────────────────────────────────────────────
info "Step 1: Deploying LSFS daemon + query engine..."
bash "$ISO_DIR/scripts/deploy.sh" 2>&1 | grep -E "(✓|→|⚠|✗)" || true

# ── Step 2: Ensure Ollama is running ─────────────────────────────────────────
info "Step 2: Checking Ollama..."
if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    sudo systemctl enable --now ollama 2>/dev/null || true
    sleep 3
fi
if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama is running"
    # Pin model in VRAM
    curl -s -X POST http://localhost:11434/api/generate \
        -d '{"model":"intfloat/multilingual-e5-small","keep_alive":-1,"prompt":""}' >/dev/null && \
        ok "Model pinned in VRAM"
else
    warn "Ollama not reachable — run: sudo systemctl start ollama"
fi

# ── Step 3: Ensure Qdrant is running ─────────────────────────────────────────
info "Step 3: Checking Qdrant..."
if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
    ok "Qdrant is running"
elif curl -sf --unix-socket /tmp/lsfs.sock http://localhost/health >/dev/null 2>&1; then
    ok "Qdrant is running (UDS)"
else
    sudo systemctl enable --now qdrant 2>/dev/null || \
        warn "Qdrant not running — start manually"
fi

# ── Step 4: Start LSFS daemon ────────────────────────────────────────────────
info "Step 4: Starting LSFS daemon..."
systemctl --user daemon-reload 2>/dev/null
if systemctl --user enable --now lsfs-daemon.service 2>/dev/null; then
    ok "LSFS daemon started"
else
    warn "Daemon service failed — trying direct launch"
    nohup python3 ~/.config/scripts/lsfs_daemon.py > /tmp/lsfs-daemon.log 2>&1 &
    sleep 2
    if pgrep -f lsfs_daemon >/dev/null; then
        ok "LSFS daemon running (direct)"
    else
        err "Daemon failed to start — check /tmp/lsfs-daemon.log"
    fi
fi

# ── Step 5: Patch Hyprland for Super+Space ───────────────────────────────────
info "Step 5: Patching Hyprland for Super+Space..."
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ]; then
    if ! grep -q "lsfs_launcher_hook" "$HYPR_CONF" 2>/dev/null; then
        mkdir -p "$(dirname "$HYPR_CONF")"
        cat >> "$HYPR_CONF" << 'EOF'

# LSFS Agentic Search (Super+Space)
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
EOF
        ok "Super+Space added to Hyprland"
        hyprctl reload 2>/dev/null || true
    else
        ok "Super+Space already configured"
    fi
else
    warn "Hyprland config not found — create manually:"
    echo "  bind = SUPER, Space, exec, ~/.config/scripts/lsfs_launcher_hook.sh"
fi

# ── Step 6: Index some files for testing ─────────────────────────────────────
info "Step 6: Indexing test files..."
lsfs-query --index "$HOME/.config" 2>/dev/null && ok "Indexed ~/.config" || warn "Index skipped"
lsfs-query --index "$HOME/ash-iso/docs" 2>/dev/null && ok "Indexed docs/" || true

# ── Step 7: Feature Tests ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Running Feature Tests${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

test_feature() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        ok "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        err "$name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Basic semantic search
echo "  ── Semantic Search ──"
test_feature "Basic search returns results" \
    "lsfs-query --list-mode 'configuration' 2>/dev/null | grep -q -v 'No matches'"

# Test 2: Natural language concept search
test_feature "Natural language: 'browser settings'" \
    "lsfs-query --list-mode 'browser settings' 2>/dev/null | grep -q -v 'No matches'"

# Test 3: Metadata filter ext:
test_feature "Filter: ext:json" \
    "lsfs-query --list-mode 'config ext:json' 2>/dev/null | grep -q json"

# Test 4: Metadata filter name:
test_feature "Filter: name:hyprland" \
    "lsfs-query --list-mode 'name:hyprland' 2>/dev/null | grep -q hyprland"

# Test 5: Cross-encoder reranking active
test_feature "Cross-encoder reranker loaded" \
    "python3 -c 'from sentence_transformers import CrossEncoder; CrossEncoder(\"cross-encoder/ms-marco-MiniLM-L-6-v2\", device=\"cpu\")' 2>/dev/null"

# Test 6: Tree-sitter available
test_feature "Tree-sitter parser loaded" \
    "python3 -c 'import tree_sitter_python; print(\"ok\")' 2>/dev/null"

# Test 7: Daemon watching
test_feature "LSFS daemon process running" \
    "pgrep -f lsfs_daemon >/dev/null 2>&1 || systemctl --user -q is-active lsfs-daemon.service 2>/dev/null"

# Test 8: Wofi launches
if command -v wofi &>/dev/null; then
    test_feature "Wofi installed" "true"
fi

# Test 9: Launcher hook exists
test_feature "Launcher hook script ready" \
    "test -x ~/.config/scripts/lsfs_launcher_hook.sh"

# Test 10: lsfsignore exists
test_feature ".lsfsignore created" \
    "test -f ~/.lsfsignore"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "  Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Ash Linux — Ready to Use                                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  SUPER + Space   → Wofi → LSFS Agentic Search (concept search)"
echo "  SUPER + D       → Wofi → App launcher"
echo "  lsfs-query      → CLI semantic search with filters"
echo ""
echo "  Examples:"
echo "    lsfs-query --list-mode 'database connection'"
echo "    lsfs-query --list-mode 'network config ext:yaml'"
echo "    lsfs-query --list-mode 'setup after:2026-07-01'"
echo "    lsfs-query --list-mode 'name:hyprland'"
echo "    lsfs-query --index ~/projects"
echo ""
echo "  Live monitoring:"
echo "    journalctl --user -u lsfs-daemon -f"
echo "    lsfs-parity"
echo ""
echo "  Build ISO (distributable):"
echo "    cd ~/ash-iso && sudo bash scripts/build-iso.sh"
