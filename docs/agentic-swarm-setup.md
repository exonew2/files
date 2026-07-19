# Ash Agentic Swarm Habitat — Setup Guide

*Deploy the full LSFS (Local LLM-Based Semantic File System) with Hyprland, Wofi, Qdrant, and Claude Code on ash-iso.*

---

## Part 1: Host Hardware Fix (VMware)

Before booting the VM, stabilize the VMware virtual GPU for Wayland:

1. **Shut down the VM** if running.
2. On your **host machine**, open the VM's `.vmx` file in a text editor:
   ```bash
   # macOS / Linux
   vim ~/Documents/Virtual\ Machines/ash-iso/ash-iso.vmx
   ```
3. **Append** these two lines at the bottom:
   ```text
   mks.enableVulkanRenderer = "FALSE"
   svga.disableFIFO = "TRUE"
   ```
4. Save, close, and **boot the VM**.

> *Why:* VMware's Vulkan renderer causes Hyprland/Wayland to tear, freeze, or show black boxes. Disabling it falls back to the stable SVGA GPU. `LIBGL_ALWAYS_SOFTWARE` (used inside the VM) prevents OpenGL crashes during heavy install operations.

---

## Part 2: VM-Side Agentic OS Deployment

Boot the VM. At the GNOME/Hyprland desktop, open a CPU-rendered terminal:

```bash
LIBGL_ALWAYS_SOFTWARE=true kitty
```

> This prevents the OpenGL driver from crashing under heavy installation I/O.

Now paste the full script block below. It is idempotent and safe to re-run.

```bash
#!/usr/bin/env bash
# =============================================================================
# Ash Agentic Swarm Habitat — Master Setup Script
# Transforms ash-iso into a fully vector-aware agentic OS with:
#   - Wofi (stable Wayland launcher, replaces rofi)
#   - SwayNC (notification center)
#   - Qdrant + Ollama (local vector AI memory)
#   - LSFS (semantic file search engine)
#   - Claude Code + OpenClaw (AI coding agents)
# =============================================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

# ── Config ──────────────────────────────────────────────────────────────────
USER_HOME="$HOME"
LSFS_SCRIPTS="$HOME/.config/scripts"
BIN_DIR="$HOME/.local/bin"
QDRANT_DIR="$HOME/.local/share/qdrant"
NPM_PREFIX="$HOME/.npm-global"

# ── Step 1: System Package Trades ──────────────────────────────────────────
info "Step 1: Replacing rofi → wofi, dunst → swaync..."
sudo pacman -S --needed --noconfirm \
  wofi swaync jq >/dev/null 2>&1 || true

# Remove rofi/dunst if installed (conflict with wofi/swaync)
sudo pacman -R --noconfirm rofi dunst 2>/dev/null || true

ok "Packages ready"

# ── Step 2: Fix NPM for global installs (no sudo) ──────────────────────────
info "Step 2: Configuring NPM prefix..."
mkdir -p "$NPM_PREFIX"
npm config set prefix "$NPM_PREFIX" 2>/dev/null || true

# Add to PATH persistently
if ! grep -q "npm-global" "$HOME/.bash_profile" 2>/dev/null; then
  echo "export PATH=\"$NPM_PREFIX/bin:\$PATH\"" >> "$HOME/.bash_profile"
fi
export PATH="$NPM_PREFIX/bin:$PATH"

ok "NPM prefix set to $NPM_PREFIX"

# ── Step 3: Install AI Coding Agents ────────────────────────────────────────
info "Step 3: Installing Claude Code & OpenClaw..."
npm install -g @anthropic-ai/claude-code openclaw 2>/dev/null || warn "npm install failed — try: npm install -g @anthropic-ai/claude-code openclaw"
ok "AI agents installed (if npm succeeded)"

# ── Step 4: Wofi Config (Catppuccin Mocha) ─────────────────────────────────
info "Step 4: Configuring Wofi..."
mkdir -p "$HOME/.config/wofi"

cat > "$HOME/.config/wofi/config" << 'WOFIGO'
mode=dmenu
width=600
height=400
allow_markup=false
prompt=Agentic Search
allow_images=false
show=drun
insensitive=true
filter_rate=100
WOFIGO

cat > "$HOME/.config/wofi/style.css" << 'WOFICSS'
window {
    margin: 0px;
    border: 3px solid #89b4fa;
    background-color: #1e1e2e;
    border-radius: 10px;
    font-family: "JetBrains Mono", "Noto Sans", sans-serif;
    font-size: 13px;
}
#input {
    margin: 8px;
    border: 1px solid #45475a;
    border-radius: 6px;
    padding: 6px 10px;
    color: #cdd6f4;
    background-color: #313244;
    font-size: 14px;
}
#inner-box { margin: 4px; border: none; background-color: #1e1e2e; }
#outer-box { margin: 4px; border: none; background-color: #1e1e2e; }
#scroll { margin: 2px; border: none; background-color: #1e1e2e; }
#text { margin: 4px 8px; border: none; color: #cdd6f4; }
#entry {
    border-radius: 6px;
    padding: 4px;
}
#entry:selected { background-color: #313244; border-radius: 6px; }
#text:selected { color: #f38ba8; }
#img { margin-right: 8px; }
WOFICSS

ok "Woofi configured"

# ── Step 5: SwayNC Config (Notification Center) ────────────────────────────
info "Step 5: Configuring SwayNC..."
mkdir -p "$HOME/.config/swaync"

cat > "$HOME/.config/swaync/config.json" << 'SWAYNCCFG'
{
  "$schema": "/etc/xdg/swaync/configSchema.json",
  "positionX": "right",
  "positionY": "top",
  "layer": "overlay",
  "control-center-layer": "top",
  "layer-shell": true,
  "cssPriority": "user",
  "notification-icon-size": 48,
  "notification-body-image-height": 160,
  "notification-body-image-width": 200,
  "timeout": 6,
  "timeout-low": 4,
  "timeout-critical": 0,
  "fit-to-screen": true,
  "control-center-margin-top": 4,
  "control-center-margin-bottom": 4,
  "control-center-margin-right": 4,
  "control-center-margin-left": 4,
  "notification-window-width": 380,
  "keyboard-shortcuts": true,
  "image-visibility": "when-available",
  "transition-time": 200,
  "hide-on-clear": false,
  "hide-on-action": true,
  "script-fail-notify": true,
  "scripts": {
    "example-script": { "exec": "echo 'swaync notification' >> /tmp/swaync.log", "urgency": "Normal" }
  }
}
SWAYNCCFG

cat > "$HOME/.config/swaync/style.css" << 'SWAYNCSS'
* {
  font-family: "JetBrains Mono", "Noto Sans", sans-serif;
}
.notification-row { outline: none; }
.notification-row:focus, .notification-row:hover { background: #313244; }
.notification {
  border-radius: 10px;
  margin: 6px 8px;
  box-shadow: 0 2px 6px rgba(0,0,0,0.3);
  background: #1e1e2e;
  border: 1px solid #45475a;
}
.notification-content { background: transparent; padding: 6px; }
.close-button {
  background: #f38ba8;
  color: #1e1e2e;
  text-shadow: none;
  padding: 0 6px;
  border-radius: 4px;
  margin: 4px;
}
.close-button:hover { background: #f9e2af; }
.notification-default-action:hover { background: #313244; }
.summary { color: #89b4fa; font-size: 14px; font-weight: bold; }
.time { color: #a6adc8; font-size: 11px; }
.body { color: #cdd6f4; font-size: 13px; }
.control-center {
  background: #1e1e2e;
  border: 1px solid #45475a;
  border-radius: 12px;
  margin: 8px;
  padding: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.4);
}
.control-center-list { background: transparent; }
.floating-notifications { background: transparent; }
.widget-title { color: #cdd6f4; font-size: 16px; font-weight: bold; margin: 8px; }
.widget-title button { color: #f38ba8; border: none; background: transparent; }
.widget-label { margin: 8px; }
.widget-label span { color: #cdd6f4; font-size: 14px; }
SWAYNCSS

ok "SwayNC configured"

# ── Step 6: Patch Hyprland Config for Wofi + SwayNC ────────────────────────
info "Step 6: Patching Hyprland config..."

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

# Replace rofi launchers with wofi
sed -i 's|rofi -show drun|wofi --show drun|g' "$HYPR_CONF"
sed -i 's|rofi -show run|wofi --show run|g' "$HYPR_CONF"

# Swap exec-once: dunst → swaync
sed -i 's|exec-once = dunst|exec-once = swaync|g' "$HYPR_CONF"

# Add LSFS launcher hook for Super+Space if not present
if ! grep -q "lsfs_launcher_hook" "$HYPR_CONF"; then
  cat >> "$HYPR_CONF" << 'HYPRPATCH'

# --- Agentic Search (Super+Space → Wofi → LSFS Semantic Query) ---
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
HYPRPATCH
fi

# Ensure NPM path is in hyprland env
if ! grep -q "npm-global" "$HYPR_CONF"; then
  sed -i '/^env = PATH/a env = PATH,'"$NPM_PREFIX/bin"':\$PATH' "$HYPR_CONF" 2>/dev/null || true
fi

ok "Hyprland patched"

# ── Step 7: Qdrant Vector Database ─────────────────────────────────────────
info "Step 7: Deploying Qdrant vector DB..."

# Check if qdrant is available as system package or binary
if ! command -v qdrant &>/dev/null; then
  # Download standalone binary
  mkdir -p "$BIN_DIR"
  LATEST=$(curl -sI https://github.com/qdrant/qdrant/releases/latest | grep -i location | grep -oP '\d+\.\d+\.\d+' | head -1)
  curl -sL "https://github.com/qdrant/qdrant/releases/download/v${LATEST}/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
    | tar -xz -C "$BIN_DIR" 2>/dev/null && \
  chmod +x "$BIN_DIR/qdrant" || \
  warn "Qdrant download failed — install manually: https://github.com/qdrant/qdrant/releases"
fi

mkdir -p "$QDRANT_DIR"

# User systemd service for Qdrant
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/qdrant.service" << 'QDSRV'
[Unit]
Description=Qdrant Vector Database
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/qdrant --storage %h/.local/share/qdrant
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=default.target
QDSRV

systemctl --user daemon-reload
systemctl --user enable --now qdrant.service 2>/dev/null || warn "Qdrant user service failed to start"

ok "Qdrant deployed"

# ── Step 8: Ollama + Embedding Model ────────────────────────────────────────
info "Step 8: Configuring Ollama for embeddings..."
sudo systemctl enable --now ollama.service 2>/dev/null || true

# Wait for Ollama to be ready
for i in $(seq 1 10); do
  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama ready"
    break
  fi
  sleep 1
done

# Pull the lightweight embedding model
ollama pull nomic-embed-text 2>/dev/null || warn "ollama pull failed — run: ollama pull nomic-embed-text"
ok "Embedding model ready"

# ── Step 9: LSFS Python Semantic Search Engine ─────────────────────────────
info "Step 9: Deploying LSFS semantic search engine..."

mkdir -p "$LSFS_SCRIPTS"

cat > "$LSFS_SCRIPTS/lsfs_query.py" << 'PYLSFS'
#!/usr/bin/env python3
"""
lsfs_query.py — Local LLM-Based Semantic File System Query Engine.
Performs hybrid search combining vector embeddings + fuzzy keyword fallback.
Safe for Wayland environments: uses strict timeouts, no SIGPIPE-prone pipes.
"""
import sys, json, subprocess, argparse, urllib.request, urllib.error, time

OLLAMA_URL = "http://localhost:11434/api/embeddings"
QDRANT_URL = "http://localhost:6333/collections"

def req(url, method="GET", data=None, timeout=1.5):
    if data is not None:
        data = json.dumps(data).encode("utf-8")
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        return {}

def ensure_collection():
    """Create the 'apps' collection if it doesn't exist."""
    info = req(f"{QDRANT_URL}/apps", timeout=1.0)
    if "result" not in info:
        create = req(f"{QDRANT_URL}", "PUT", {
            "name": "apps",
            "vectors": {"size": 768, "distance": "Cosine"}
        }, timeout=2.0)

def search_semantic(query, limit=3):
    """Vector search via Ollama embedding + Qdrant."""
    emb = req(OLLAMA_URL, "POST", {"model": "nomic-embed-text", "prompt": query}, timeout=2.0)
    embedding = emb.get("embedding")
    if not embedding:
        return []

    hits = req(
        f"{QDRANT_URL}/apps/points/search", "POST",
        {"vector": embedding, "limit": limit, "with_payload": True},
        timeout=1.5
    )
    results = []
    for hit in hits.get("result", []):
        score = hit.get("score", 0)
        if score > 0.35:
            payload = hit.get("payload", {})
            results.append({
                "path": payload.get("path", ""),
                "name": payload.get("name", ""),
                "type": payload.get("type", "file"),
                "score": score,
                "method": "semantic"
            })
    return results

def search_keyword(query, max_results=5):
    """Fuzzy keyword fallback using grep — no head/pipe to avoid SIGPIPE."""
    words = query.lower().split()
    if not words:
        return []
    try:
        cmd = "find /home/aiuser /etc /usr/share -maxdepth 6 -type f 2>/dev/null"
        for w in words:
            cmd += f" | grep -i -- '{w}'"
        cmd += f" | tail -n {max_results}"
        output = subprocess.check_output(cmd, shell=True, text=True, timeout=3.0)
        files = [f.strip() for f in output.splitlines() if f.strip()]
        return [{"path": f, "name": f.split("/")[-1], "type": "file", "score": 0.5, "method": "keyword"} for f in files[:max_results]]
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return []

def index_file(filepath):
    """Index a single file into Qdrant."""
    try:
        with open(filepath, "r", errors="ignore") as f:
            content = f.read(2048)
        if not content.strip():
            return
        emb = req(OLLAMA_URL, "POST", {"model": "nomic-embed-text", "prompt": content[:1024]}, timeout=2.0)
        embedding = emb.get("embedding")
        if not embedding:
            return
        req(f"{QDRANT_URL}/apps/points", "PUT", {
            "points": [{
                "id": abs(hash(filepath)) % (2**63),
                "vector": embedding,
                "payload": {
                    "path": filepath,
                    "name": filepath.split("/")[-1],
                    "type": "file"
                }
            }]
        }, timeout=2.0)
    except Exception:
        pass

def scan_and_index(base_path, max_files=50):
    """Scan a directory and index files."""
    count = 0
    for root, dirs, files in os.walk(base_path):
        if count >= max_files:
            break
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fname in files:
            if count >= max_files:
                break
            fpath = os.path.join(root, fname)
            if os.path.isfile(fpath) and not os.path.islink(fpath):
                index_file(fpath)
                count += 1
    return count

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LSFS Semantic Search")
    parser.add_argument("--list-mode", type=str, help="Query string to search for")
    parser.add_argument("--index", type=str, help="Path to index")
    args = parser.parse_args()

    if args.index:
        import os
        ensure_collection()
        n = scan_and_index(args.index)
        print(f"Indexed {n} files")
        sys.exit(0)

    if args.list_mode:
        ensure_collection()
        results = search_semantic(args.list_mode)
        if not results:
            results = search_keyword(args.list_mode)
        if not results:
            print(f"/home/aiuser | No matches for '{args.list_mode}'.")
        else:
            for r in results:
                label = f"{r['path']} | {r['method'].title()}: {r['name']}"
                if r['method'] == 'semantic':
                    label += f" ({r['score']:.2f})"
                print(label)
        sys.exit(0)

    print("Usage: lsfs_query.py --list-mode <query> | --index <path>")
PYLSFS

chmod +x "$LSFS_SCRIPTS/lsfs_query.py"

# Create symlink in PATH
mkdir -p "$BIN_DIR"
ln -sf "$LSFS_SCRIPTS/lsfs_query.py" "$BIN_DIR/lsfs-query"

ok "LSFS engine deployed"

# ── Step 10: Wofi LSFS Launcher Hook ────────────────────────────────────────
info "Step 10: Deploying Wofi→LSFS launcher hook..."

cat > "$LSFS_SCRIPTS/lsfs_launcher_hook.sh" << 'LSFSHOOK'
#!/usr/bin/env bash
# lsfs_launcher_hook.sh — SUPER+SPACE → Wofi → Semantic File Search
# Uses --exec-search to prevent empty-list freeze on VMware virtual GPU.

set -euo pipefail

QUERY=$(wofi --dmenu --prompt "Agentic Search" --exec-search --cache-file /dev/null < /dev/null)

if [[ -z "${QUERY:-}" ]]; then
    exit 0
fi

# Notify: search in progress (background to not block UI)
notify-send -t 1500 "Agentic OS" "Searching: $QUERY" &

# Run LSFS query (with timeout to prevent UI hang)
timeout 5 python3 "$HOME/.config/scripts/lsfs_query.py" --list-mode "$QUERY" > /tmp/lsfs_results.txt 2>/dev/null

# Show results in wofi
SELECTED=$(wofi --dmenu --prompt "Results" --cache-file /dev/null < /tmp/lsfs_results.txt)

if [[ -z "${SELECTED:-}" ]]; then
    exit 0
fi

# Extract path (before the first " | ")
TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//')

if [[ -d "$TARGET_PATH" ]]; then
    kitty -e yazi "$TARGET_PATH" &
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then
    gtk-launch "$(basename "$TARGET_PATH")" &
else
    kitty --class floating_editor -e nvim "$TARGET_PATH" &
fi
LSFSHOOK

chmod +x "$LSFS_SCRIPTS/lsfs_launcher_hook.sh"

ok "Launcher hook deployed"

# ── Step 11: Index Home Directory for LSFS ──────────────────────────────────
info "Step 11: Indexing home directory into Qdrant..."
python3 "$LSFS_SCRIPTS/lsfs_query.py" --index "$HOME" 2>/dev/null || warn "Initial indexing skipped"
ok "Indexing complete (if Qdrant was reachable)"

# ── Step 12: Reload Hyprland ────────────────────────────────────────────────
info "Step 12: Reloading Hyprland..."
hyprctl reload 2>/dev/null || true
ok "Hyprland reloaded"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Ash Agentic Swarm Habitat — Deployment Complete       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  SUPER + Return  → Kitty terminal"
echo "  SUPER + D       → Wofi (app launcher)"
echo "  SUPER + Space   → Wofi → LSFS Agentic Search"
echo "  SUPER + Q       → Close window"
echo "  SUPER + SHIFT+Q → Exit Hyprland"
echo ""
echo "  Qdrant:  http://localhost:6333"
echo "  Ollama:  http://localhost:11434"
echo ""
echo "  To index more files into LSFS:"
echo "    lsfs-query --index ~/projects"
echo ""
echo "  To search from terminal:"
echo "    lsfs-query --list-mode 'find my notes about arch'"
echo ""
```

---

## Part 3: Verification

Test each component:

```bash
# Wofi launches
wofi --show drun

# SwayNC notifications
notify-send "Test" "Agentic OS notification center works"

# Qdrant is running
curl http://localhost:6333/dashboard

# Ollama embeddings work
curl -X POST http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"test"}'

# LSFS semantic search
lsfs-query --list-mode "configuration files"

# Claude Code
claude --help

# OpenClaw
openclaw --help
```

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Hyprland WM                       │
│  ┌────────┐  ┌──────────┐  ┌─────────────────────┐  │
│  │ Waybar  │  │  SwayNC  │  │  Wofi (Launcher)    │  │
│  │ (panel) │  │ (notifs) │  │  SUPER+SPACE → LSFS │  │
│  └────────┘  └──────────┘  └─────────┬───────────┘  │
│                                       │              │
│                    ┌──────────────────┴──────┐       │
│                    │  lsfs_launcher_hook.sh   │       │
│                    │  (bash wrapper, timeout) │       │
│                    └──────────┬───────────────┘       │
│                               │                       │
│                    ┌──────────┴──────────────┐        │
│                    │  lsfs_query.py          │        │
│                    │  (Python hybrid search) │        │
│                    └──────┬──────────┬───────┘        │
│                           │          │                │
│                 ┌─────────┴┐  ┌──────┴───────┐        │
│                 │  Ollama  │  │   Qdrant     │        │
│                 │embedding │  │ vector store │        │
│                 └──────────┘  └──────────────┘        │
│                                                       │
│  AI Agents:  Claude Code  ·  OpenClaw                │
└─────────────────────────────────────────────────────┘
```
