#!/usr/bin/env bash
set -euo pipefail

ISO_DIR="${1:-$HOME/ash-iso}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

FIXED=()

echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}  LSFS Health Check + Auto-Fix${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"

if ! curl -sf http://localhost:6333/health >/dev/null 2>&1 && ! curl -sf --unix-socket /tmp/lsfs.sock http://localhost/health >/dev/null 2>&1; then
    info "Qdrant not running — attempting start..."
    if systemctl --user start qdrant.service 2>/dev/null || sudo systemctl start qdrant 2>/dev/null; then
        ok "Qdrant started"
        notify-send -t 3000 "LSFS Fix" "Qdrant service started" 2>/dev/null || true
        FIXED+=("Qdrant started")
    else
        warn "Could not start Qdrant — try: sudo systemctl start qdrant"
    fi
else
    ok "Qdrant already running"
fi

for i in 1 2 3 4 5; do
    if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    info "Ollama not running — attempting start..."
    if systemctl --user start ollama.service 2>/dev/null || sudo systemctl start ollama 2>/dev/null; then
        sleep 3
        ok "Ollama started"
        notify-send -t 3000 "LSFS Fix" "Ollama service started" 2>/dev/null || true
        FIXED+=("Ollama started")
    else
        warn "Could not start Ollama — try: sudo systemctl start ollama"
    fi
else
    ok "Ollama already running"
fi

if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    if ! curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -q nomic-embed-text; then
        info "Pulling nomic-embed-text model..."
        if curl -sf -X POST http://localhost:11434/api/pull -d '{"model":"nomic-embed-text"}' >/dev/null 2>&1; then
            ok "Model pulled"
            notify-send -t 3000 "LSFS Fix" "nomic-embed-text model pulled" 2>/dev/null || true
            FIXED+=("nomic-embed-text model pulled")
        else
            warn "Failed to pull nomic-embed-text"
        fi
    else
        ok "nomic-embed-text model already present"
    fi

    if curl -sf -X POST http://localhost:11434/api/generate -d '{"model":"nomic-embed-text","keep_alive":-1,"prompt":"warmup"}' >/dev/null 2>&1; then
        ok "Model pinned in VRAM"
    else
        warn "Could not pin model in VRAM"
    fi
fi

mkdir -p "$HOME/.config/scripts" "$HOME/.local/bin"
ok "Config directories ready"

LAUNCHER_DST="$HOME/.config/scripts/lsfs_launcher_hook.sh"
if [ ! -f "$LAUNCHER_DST" ]; then
    info "Creating launcher hook..."
    cat > "$LAUNCHER_DST" << 'LSFSHOOK'
#!/usr/bin/env bash
set -euo pipefail

QUERY=$(wofi --dmenu --prompt "Agentic Search" --cache-file /dev/null < /dev/null 2>/dev/null) || true
[ -z "${QUERY:-}" ] && exit 0

notify-send -t 3000 -r 999 "Agentic OS" "Searching: $QUERY"

RESULTS_FILE=$(mktemp /tmp/lsfs_results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT

SEARCH_ERR=""
HAS_RESULTS=0

PYSCRIPT="$HOME/.config/scripts/lsfs_query.py"
if [ -f "$PYSCRIPT" ]; then
    timeout 10 python3 "$PYSCRIPT" --list-mode "$QUERY" > "$RESULTS_FILE" 2>/tmp/lsfs_err.$$ || true
    SEARCH_ERR=$(cat /tmp/lsfs_err.$$ 2>/dev/null)
    rm -f /tmp/lsfs_err.$$
    if [ -s "$RESULTS_FILE" ] && ! head -1 "$RESULTS_FILE" | grep -q "No matches"; then
        HAS_RESULTS=1
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    if echo "$SEARCH_ERR" | grep -qi "ollama\|connect.*11434\|timeout\|refused"; then
        notify-send -u critical -t 5000 "Agentic OS" "Ollama not running — start with: systemctl start ollama"
    elif echo "$SEARCH_ERR" | grep -qi "qdrant\|connect.*6333\|refused"; then
        notify-send -u critical -t 5000 "Agentic OS" "Qdrant not running — start with: systemctl start qdrant"
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    python3 - "$QUERY" > "$RESULTS_FILE" 2>/tmp/lsfs_fb_err.$$ << 'PYFALLBACK' || true
import sys, json, os, urllib.request, http.client, socket
OLLAMA_URL = "http://localhost:11434/api/embeddings"
MODEL = "nomic-embed-text"
QDRANT_SOCKET = "/tmp/lsfs.sock"
QDRANT_TCP = "http://localhost:6333"
COSINE_FLOOR = 0.5
SEARCH_LIMIT = 20
def qdrant_req(method, path, data=None, timeout=2):
    api_path = f"/collections/apps/{path.lstrip('/')}"
    body = json.dumps(data).encode() if data else None
    headers = {"Content-Type": "application/json"}
    if os.path.exists(QDRANT_SOCKET):
        try:
            conn = http.client.HTTPConnection("localhost", timeout=timeout)
            conn.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            conn.sock.settimeout(timeout)
            conn.sock.connect(QDRANT_SOCKET)
            conn.request(method, api_path, body=body, headers=headers)
            resp = conn.getresponse()
            result = json.loads(resp.read())
            conn.close()
            return result
        except Exception:
            pass
    url = f"{QDRANT_TCP}{api_path}"
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return {}
def ensure_collection():
    info = qdrant_req("GET", "", timeout=1.0)
    return "result" in info
def search(query, limit=SEARCH_LIMIT):
    req = urllib.request.Request(OLLAMA_URL, data=json.dumps({"model": MODEL, "prompt": query[:2048], "keep_alive": -1}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3.0) as resp:
        emb_data = json.loads(resp.read())
    embedding = emb_data.get("embedding")
    if not embedding:
        sys.exit(1)
    search_payload = {"vector": embedding, "limit": limit, "with_payload": True}
    hits = qdrant_req("POST", "points/search", search_payload, timeout=2.0)
    results = []
    seen_paths = set()
    for hit in hits.get("result", []):
        score = hit.get("score", 0)
        payload = hit.get("payload", {})
        path = payload.get("path", "")
        if score < COSINE_FLOOR or path in seen_paths:
            continue
        seen_paths.add(path)
        results.append({"path": path, "name": payload.get("name", ""), "score": score})
    results.sort(key=lambda r: r['score'], reverse=True)
    return results
if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else ""
    if not query:
        sys.exit(1)
    if not ensure_collection():
        print("| No matches (Qdrant collection not found)")
        sys.exit(0)
    results = search(query)
    if not results:
        print(f"| No matches found for '{query}'.")
    for r in results:
        print(f"{r['path']} | {r['name']} ({r['score']:.3f})")
PYFALLBACK
    FB_ERR=$(cat /tmp/lsfs_fb_err.$$ 2>/dev/null)
    rm -f /tmp/lsfs_fb_err.$$
    if [ -s "$RESULTS_FILE" ] && ! head -1 "$RESULTS_FILE" | grep -q "No matches"; then
        HAS_RESULTS=1
    elif [ "$HAS_RESULTS" -eq 0 ] && [ -n "$FB_ERR" ]; then
        if echo "$FB_ERR" | grep -qi "ollama\|connect.*11434\|refused\|timeout\|timed out"; then
            notify-send -u critical -t 5000 "Agentic OS" "Ollama not running — start with: systemctl start ollama"
        elif echo "$FB_ERR" | grep -qi "qdrant\|connect.*6333\|refused"; then
            notify-send -u critical -t 5000 "Agentic OS" "Qdrant not running — start with: systemctl start qdrant"
        elif echo "$FB_ERR" | grep -qi "error"; then
            notify-send -u critical -t 5000 "Agentic OS" "Search error: $FB_ERR"
        fi
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    PAT=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ')
    if [ -n "$PAT" ]; then
        if echo "$PAT" | grep -qiE '[0-9]+\s*(h|hr|hour|hours)'; then
            H=$(echo "$PAT" | grep -oE '[0-9]+')
            TIME_ARG="${H}h"
        else
            D=$(echo "$PAT" | grep -oE '[0-9]+')
            TIME_ARG="${D}d"
        fi
        if command -v fd &>/dev/null; then
            fd --changed-within "$TIME_ARG" --type f "$HOME" 2>/dev/null | head -30 > "$RESULTS_FILE" || true
        elif command -v find &>/dev/null; then
            if echo "$TIME_ARG" | grep -q 'h$'; then
                MINS=$(( ${TIME_ARG%h} * 60 ))
            else
                MINS=$(( ${TIME_ARG%d} * 1440 ))
            fi
            find "$HOME" -mmin "-${MINS}" -type f 2>/dev/null | head -30 > "$RESULTS_FILE" || true
        fi
        [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ] && command -v fd &>/dev/null; then
    fd --type f --max-depth 5 "$HOME" 2>/dev/null | head -15 > "$RESULTS_FILE" || true
    [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
fi

notify-send -t 2000 -r 999 "Agentic OS" "$(wc -l < "$RESULTS_FILE") results ready"

SELECTED=$(wofi --dmenu --prompt "Results ($(wc -l < "$RESULTS_FILE") files)" --cache-file /dev/null < "$RESULTS_FILE" 2>/dev/null) || true
[ -z "${SELECTED:-}" ] && exit 0

TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//; s/\t.*//')
[ -z "$TARGET_PATH" ] && exit 0
[ ! -e "$TARGET_PATH" ] && notify-send -u critical -t 5000 "Agentic OS" "File not found: $TARGET_PATH" && exit 1

if [ -d "$TARGET_PATH" ]; then
    hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'"
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then
    hyprctl dispatch exec "gtk-launch '$(basename "$TARGET_PATH")'"
else
    hyprctl dispatch exec "kitty --class floating_editor -e nvim '$TARGET_PATH'"
fi
LSFSHOOK
    chmod +x "$LAUNCHER_DST"
    ok "Launcher hook created"
    notify-send -t 3000 "LSFS Fix" "Launcher hook created" 2>/dev/null || true
    FIXED+=("Launcher hook created")
else
    ok "Launcher hook already present"
fi

SYSD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSD_DIR"
SVC="$SYSD_DIR/lsfs-daemon.service"
if [ ! -f "$SVC" ]; then
    info "Creating systemd service..."
    cat > "$SVC" << 'SYSD'
[Unit]
Description=LSFS Daemon -- Semantic File Indexer
Documentation=https://github.com/ash-linux/ash-iso
After=network.target ollama.service qdrant.service
Wants=qdrant.service ollama.service

[Service]
Type=simple
ExecStart=%h/.config/scripts/lsfs_daemon.py
ExecStartPost=/usr/bin/bash -c 'sleep 5 && %h/.config/scripts/lsfs_query.py --list-mode "warmup vector indices" >/dev/null 2>&1 || true'
Restart=always
RestartSec=5
Nice=19
IOSchedulingClass=idle
CPUQuota=30%
Environment=PYTHONUNBUFFERED=1
Environment=QDRANT__STORAGE__WAL__WAL_FLUSH_INTERVAL_MS=1000
Environment=QDRANT__SERVICE__GRPC_PORT=6334
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SYSD
    ok "Systemd service created"
    notify-send -t 3000 "LSFS Fix" "Systemd service created" 2>/dev/null || true
    FIXED+=("lsfs-daemon.service created")
else
    ok "Systemd service already exists"
fi

systemctl --user daemon-reload 2>/dev/null || true
if ! systemctl --user is-active lsfs-daemon.service >/dev/null 2>&1; then
    info "Starting daemon..."
    if systemctl --user enable --now lsfs-daemon.service 2>/dev/null; then
        ok "Daemon started"
        notify-send -t 3000 "LSFS Fix" "LSFS daemon started" 2>/dev/null || true
        FIXED+=("lsfs-daemon enabled and started")
    else
        warn "Daemon service failed"
    fi
else
    ok "Daemon already running"
fi

for rc in bashrc zshrc; do
    rcpath="$HOME/.$rc"
    if [ -f "$rcpath" ] && ! grep -q '\.local/bin' "$rcpath" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rcpath"
        ok "PATH added to ~/.$rc"
        FIXED+=("PATH added to ~/.$rc")
    fi
done

HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ]; then
    if ! grep -q "lsfs_launcher_hook" "$HYPR_CONF" 2>/dev/null; then
        mkdir -p "$(dirname "$HYPR_CONF")"
        cat >> "$HYPR_CONF" << 'EOF'

# LSFS Agentic Search (Super+Space)
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
EOF
        ok "Super+Space bind added to Hyprland"
        notify-send -t 3000 "LSFS Fix" "Super+Space bind added" 2>/dev/null || true
        FIXED+=("Super+Space bind added")
    else
        ok "Super+Space already configured"
    fi
fi

hyprctl reload 2>/dev/null || true

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  LSFS Fix Complete${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"

if [ ${#FIXED[@]} -eq 0 ]; then
    echo -e "${GREEN}  All systems operational — nothing needed fixing${NC}"
else
    echo -e "${CYAN} Fixed:${NC}"
    for item in "${FIXED[@]}"; do
        echo -e "  ${GREEN}✓${NC} $item"
    done
    notify-send -t 5000 "LSFS Fix Complete" "${#FIXED[@]} issues fixed" 2>/dev/null || true
fi
