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

# Make launcher hook (100x upgraded)
mkdir -p ~/.config/scripts
cat > ~/.config/scripts/lsfs_launcher_hook.sh << 'LSFSHOOK'
#!/usr/bin/env bash
set -euo pipefail
QUERY=$(wofi --dmenu --prompt "🔎 Agentic Search" --exec-search --cache-file /dev/null < /dev/null)
[ -z "${QUERY:-}" ] && exit 0
notify-send -t 0 -r 999 "Agentic OS" "Searching: $QUERY" &
RESULTS_FILE=$(mktemp /tmp/lsfs_results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT

# ── Parse time patterns: "all files from 42h", "files last 3 days", "from 2h", "42h", etc ──
TIME_QUERY=0; TIME_ARG=""
PAT=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ')
if [ -n "$PAT" ]; then
    TIME_QUERY=1
    if echo "$PAT" | grep -qiE '[0-9]+\s*(h|hr|hour|hours)'; then
        H=$(echo "$PAT" | grep -oE '[0-9]+')
        TIME_ARG="${H}h"
    elif echo "$PAT" | grep -qiE '[0-9]+\s*(d|day|days)'; then
        D=$(echo "$PAT" | grep -oE '[0-9]+')
        TIME_ARG="${D}h"
        notify-send -t 0 -r 999 "Agentic OS" "Time filter: $D days" &
    fi
fi

# ── Strategy 1: Semantic search (concept + time filters) ──
timeout 10 python3 ~/.config/scripts/lsfs_query.py --list-mode "$QUERY" > "$RESULTS_FILE" 2>/dev/null
HAS_RESULTS=0
if [ -s "$RESULTS_FILE" ] && ! grep -q "No matches" "$RESULTS_FILE"; then
    HAS_RESULTS=1
fi

# ── Strategy 2: Time-based fd search (captures "files from 42h", "all files from 42h", etc) ──
if [ "$TIME_QUERY" -eq 1 ] && [ "$HAS_RESULTS" -eq 0 ]; then
    if command -v fd &>/dev/null; then
        fd --changed-within "$TIME_ARG" --type f ~ 2>/dev/null | head -30 > "$RESULTS_FILE"
    elif command -v find &>/dev/null; then
        MINS=$(( ${TIME_ARG%h} * 60 ))
        find ~ -mmin -$MINS -type f 2>/dev/null | head -30 > "$RESULTS_FILE"
    fi
    [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
fi

# ── Strategy 3: Universal fd search (any unmatched query) ──
if [ "$HAS_RESULTS" -eq 0 ]; then
    if command -v fd &>/dev/null; then
        WORDS=$(echo "$QUERY" | tr ' ' '\n' | grep -vE '(all|from|the|of|in|my|files|for|with|and|or|a|an|is|are|to|last|within|past|since|recent|modified|changed|show|list|find|give|get)' | head -3 | tr '\n' '|')
        if [ -n "$WORDS" ]; then
            fd --type f "${QUERY%% *}" ~ 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        else
            fd --type f --max-depth 5 ~ 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        fi
    fi
    [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
fi

notify-send -t 500 -r 999 "Agentic OS" "$(wc -l < "$RESULTS_FILE") results ready" &
SELECTED=$(wofi --dmenu --prompt "📄 Results ($(wc -l < "$RESULTS_FILE") files)" --cache-file /dev/null < "$RESULTS_FILE")
[ -z "${SELECTED:-}" ] && exit 0
TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//; s/\t.*//')
[ ! -e "$TARGET_PATH" ] && notify-send -u critical "Not found" && exit 1
if [ -d "$TARGET_PATH" ]; then hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'"
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then hyprctl dispatch exec "gtk-launch '$(basename "$TARGET_PATH')"'
else hyprctl dispatch exec "kitty --class floating_editor -e nvim '$TARGET_PATH'"; fi
LSFSHOOK
chmod +x ~/.config/scripts/lsfs_launcher_hook.sh
ok "Launcher hook created"

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
