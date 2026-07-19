#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

ISO_DIR="${1:-$HOME/ash-iso}"
cd "$ISO_DIR"
info "Deploying LSFS from $ISO_DIR"

# Install Python deps
info "Installing Python packages..."
pip install --break-system-packages pyinotify PyMuPDF aiohttp sentence-transformers python-magic 2>/dev/null || \
pip install pyinotify PyMuPDF aiohttp sentence-transformers python-magic 2>/dev/null || \
warn "Some pip packages failed — install manually"

# Extract Python scripts from the markdown doc
info "Extracting LSFS daemon and query scripts..."
python3 << 'PYEXTRACT'
import re, os
with open('docs/lsfs-optimized-setup.md') as f:
    content = f.read()

scripts_dir = os.path.expanduser("~/.config/scripts")
bin_dir = os.path.expanduser("~/.local/bin")
sysd_dir = os.path.expanduser("~/.config/systemd/user")
os.makedirs(scripts_dir, exist_ok=True)
os.makedirs(bin_dir, exist_ok=True)
os.makedirs(sysd_dir, exist_ok=True)

# Extract PYDAEMON heredoc
m = re.search(r"<< 'PYDAEMON'\n(.*?)\nPYDAEMON", content, re.DOTALL)
if m:
    with open(f"{scripts_dir}/lsfs_daemon.py", 'w') as f: f.write(m.group(1))
    os.chmod(f"{scripts_dir}/lsfs_daemon.py", 0o755)
    print("Extracted: lsfs_daemon.py")

# Extract PYQUERY heredoc
m = re.search(r"<< 'PYQUERY'\n(.*?)\nPYQUERY", content, re.DOTALL)
if m:
    with open(f"{scripts_dir}/lsfs_query.py", 'w') as f: f.write(m.group(1))
    os.chmod(f"{scripts_dir}/lsfs_query.py", 0o755)
    print("Extracted: lsfs_query.py")

# Extract PARCHECK heredoc
m = re.search(r"<< 'PARCHECK'\n(.*?)\nPARCHECK", content, re.DOTALL)
if m:
    with open(f"{scripts_dir}/lsfs_parity_check.py", 'w') as f: f.write(m.group(1))
    os.chmod(f"{scripts_dir}/lsfs_parity_check.py", 0o755)
    print("Extracted: lsfs_parity_check.py")

# Symlinks
for name in ("lsfs_daemon", "lsfs_query", "lsfs_parity_check"):
    src = f"{scripts_dir}/{name}.py"
    dst = f"{bin_dir}/{name.replace('_', '-')}"
    if os.path.exists(src):
        os.symlink(src, dst) if not os.path.exists(dst) else None
        print(f"Linked: {dst}")

# Extract systemd service units
services = {
    "lsfs-daemon.service": r"<< 'SYSD'\n(.*?)\nSYSD",
    "lsfs-parity.service": r"<< 'PARSVC'\n(.*?)\nPARSVC",
    "lsfs-parity.timer": r"<< 'PARTIM'\n(.*?)\nPARTIM",
}
for fname, pattern in services.items():
    m = re.search(pattern, content, re.DOTALL)
    if m:
        with open(f"{sysd_dir}/{fname}", 'w') as f: f.write(m.group(1))
        print(f"Created: {sysd_dir}/{fname}")
PYEXTRACT

# Make launcher hook with standalone fallback
mkdir -p ~/.config/scripts
cat > ~/.config/scripts/lsfs_launcher_hook.sh << 'LSFSHOOK'
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
chmod +x ~/.config/scripts/lsfs_launcher_hook.sh
ok "Launcher hook created"

# Add ~/.local/bin to PATH in shell rc files
for rc in bashrc zshrc; do
    rcpath="$HOME/.$rc"
    if ! grep -q '\.local/bin' "$rcpath" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rcpath"
    fi
done
ok "PATH includes ~/.local/bin"

# Create .lsfsignore
cat > ~/.lsfsignore << 'IGNORE'
.*
!/.gitkeep
node_modules/ __pycache__/ *.pyc .env/ venv/ .venv/ target/ build/ dist/
*.egg-info/ site-packages/ .git/ .svn/
*.csv *.log *.sql *.db *.sqlite *.pkl *.pickle
*.mp3 *.mp4 *.png *.jpg *.ico *.svg
*.zip *.tar *.gz *.xz *.bz2 *.rar *.7z
*.o *.so *.dylib *.dll *.exe *.bin
.idea/ .vscode/ *.swp *~ .DS_Store
lost+found/ .Trash/
IGNORE
ok "lsfsignore created"

# Enable + start daemon
systemctl --user daemon-reload
systemctl --user enable --now lsfs-daemon.service 2>/dev/null && ok "LSFS daemon started" || warn "Daemon failed — run: systemctl --user start lsfs-daemon"

# Pin model in VRAM
curl -X POST http://localhost:11434/api/generate -d '{"model":"nomic-embed-text","keep_alive":-1,"prompt":""}' 2>/dev/null && ok "Model pinned" || warn "Ollama not reachable"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LSFS Deployed — Super+Space to search    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "  lsfs-query --list-mode 'query'  → CLI search"
echo "  journalctl --user -u lsfs-daemon -f  → Live logs"
echo "  lsfs-parity  → Orphan cleanup,"
