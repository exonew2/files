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

HAS_RESULTS=0

if command -v curl &>/dev/null; then
    OLLAMA_RESP=$(curl -s --max-time 5 -X POST http://localhost:11434/api/embeddings \
        -d "{\"model\":\"nomic-embed-text\",\"prompt\":\"${QUERY//\"/\\\"}\",\"keep_alive\":-1}" 2>/dev/null) || true
    if [ -n "$OLLAMA_RESP" ]; then
        EMBEDDING=$(echo "$OLLAMA_RESP" | tr -d '\n' | sed -n 's/.*"embedding":\(\[[^]]*\]\).*/\1/p') || true
        if [ -n "${EMBEDDING:-}" ]; then
            VECTOR=$(echo "$EMBEDDING" | tr -d ' \t\n')
            PAYLOAD="{\"vector\":$VECTOR,\"limit\":10,\"with_payload\":true}"
            QDRANT_RESP=""
            if [ -S /tmp/lsfs.sock ]; then
                QDRANT_RESP=$(curl -s --max-time 5 --unix-socket /tmp/lsfs.sock \
                    -X POST http://localhost/collections/apps/points/search \
                    -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null) || true
            fi
            if [ -z "${QDRANT_RESP:-}" ]; then
                QDRANT_RESP=$(curl -s --max-time 5 \
                    -X POST http://localhost:6333/collections/apps/points/search \
                    -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null) || true
            fi
            if [ -n "${QDRANT_RESP:-}" ]; then
                while IFS= read -r block; do
                    if echo "$block" | grep -q '"path"'; then
                        FPATH=$(echo "$block" | sed 's/.*"path":"\([^"]*\)".*/\1/')
                        FNAME=$(echo "$block" | sed 's/.*"name":"\([^"]*\)".*/\1/')
                        SCORE=$(echo "$block" | sed 's/.*"score":\([0-9.]*\).*/\1/')
                        [ -n "$FPATH" ] && echo "$FPATH | $FNAME ($SCORE)"
                    fi
                done < <(echo "$QDRANT_RESP" | tr -d '\n' | sed 's/},{/}\n{/g') > "$RESULTS_FILE"
                [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
            else
                notify-send -u critical -t 5000 "Agentic OS" "Qdrant not running. Start: systemctl start qdrant"
            fi
        fi
    else
        notify-send -u critical -t 5000 "Agentic OS" "Ollama not running. Start: systemctl start ollama"
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    PAT=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ') || true
    if [ -n "$PAT" ]; then
        if echo "$PAT" | grep -qiE '[0-9]+[hd]'; then
            TIME_ARG="$PAT"
        else
            NUM=$(echo "$PAT" | grep -oE '[0-9]+')
            if echo "$PAT" | grep -qiE 'h|hr|hour|hours'; then
                TIME_ARG="${NUM}h"
            else
                TIME_ARG="${NUM}d"
            fi
        fi
        if command -v fd &>/dev/null; then
            fd --changed-within "$TIME_ARG" --type f "$HOME" 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        elif command -v find &>/dev/null; then
            if echo "$TIME_ARG" | grep -q 'h$'; then
                MINS=$(( ${TIME_ARG%h} * 60 ))
            else
                MINS=$(( ${TIME_ARG%d} * 1440 ))
            fi
            find "$HOME" -mmin "-${MINS}" -type f 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        fi
        [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ] && command -v fd &>/dev/null; then
    fd --type f --max-depth 5 "$HOME" 2>/dev/null | head -15 > "$RESULTS_FILE" || true
    [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    notify-send -u critical -t 5000 "Agentic OS" "No files found for query"
    exit 0
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

# Run health check + auto-fix
bash "$ISO_DIR/scripts/fix-all.sh" "$ISO_DIR"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LSFS Deployed — Super+Space to search    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "  lsfs-query --list-mode 'query'  → CLI search"
echo "  journalctl --user -u lsfs-daemon -f  → Live logs"
echo "  lsfs-parity  → Orphan cleanup,"
