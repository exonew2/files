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

# Make launcher hook
mkdir -p ~/.config/scripts
cat > ~/.config/scripts/lsfs_launcher_hook.sh << 'LSFSHOOK'
#!/usr/bin/env bash
set -euo pipefail
QUERY=$(wofi --dmenu --prompt "Agentic Search" --exec-search --cache-file /dev/null < /dev/null)
[ -z "${QUERY:-}" ] && exit 0
notify-send -t 0 -r 999 "Agentic OS" "Searching: $QUERY" &
RESULTS_FILE=$(mktemp /tmp/lsfs_results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT

# Detect time-based queries like "files from last 42h" / "last 3 days"
TIME_QUERY=0
if echo "$QUERY" | grep -qiE '(last|within|past|since|from last|modified|recent|changed).*[0-9]+\s*(h|hr|hour|hours|d|day|days|min|minute)'; then
    TIME_QUERY=1
    # Extract time value
    TIME_VAL=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ')
    notify-send -t 0 -r 999 "Agentic OS" "Time filter: last $TIME_VAL" &
fi

# Run semantic search with time filter support
timeout 10 python3 ~/.config/scripts/lsfs_query.py --list-mode "$QUERY" > "$RESULTS_FILE" 2>/dev/null
HAS_RESULTS=0
if [ -s "$RESULTS_FILE" ] && ! grep -q "No matches" "$RESULTS_FILE"; then
    HAS_RESULTS=1
fi

# If time query and no semantic results, fall back to fd
if [ "$TIME_QUERY" -eq 1 ] && [ "$HAS_RESULTS" -eq 0 ]; then
    TIME_ARG=$(echo "$QUERY" | grep -oiE '(last|within|past|since|from last)\s+[0-9]+\s*(h|hr|hour|hours|d|day|days)' | \
        sed -E 's/(last|within|past|since|from last) +([0-9]+) +(h|hr|hour|hours)/\2h/; s/(last|within|past|since|from last) +([0-9]+) +(d|day|days)/\2h/')
    if command -v fd &>/dev/null; then
        fd --changed-within "$TIME_ARG" --type f ~ 2>/dev/null | head -20 > "$RESULTS_FILE" || true
    elif command -v find &>/dev/null; then
        find ~ -mmin -$(( ${TIME_ARG%h} * 60 )) -type f 2>/dev/null | head -20 > "$RESULTS_FILE" || true
    fi
    if [ -s "$RESULTS_FILE" ]; then
        HAS_RESULTS=1
    fi
fi

# If still no results, try fd/extended fallback
if [ "$HAS_RESULTS" -eq 0 ]; then
    if command -v fd &>/dev/null; then
        fd --type f --max-depth 8 ~ 2>/dev/null | head -20 > "$RESULTS_FILE" || true
    fi
fi

notify-send -t 500 -r 999 "Agentic OS" "Results ready" &
SELECTED=$(wofi --dmenu --prompt "Results" --cache-file /dev/null < "$RESULTS_FILE")
[ -z "${SELECTED:-}" ] && exit 0
TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//')
[ ! -e "$TARGET_PATH" ] && notify-send -u critical "Not found" && exit 1
if [ -d "$TARGET_PATH" ]; then hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'"
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then hyprctl dispatch exec "gtk-launch '$(basename "$TARGET_PATH")'"
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
curl -X POST http://localhost:11434/api/generate -d '{"model":"intfloat/multilingual-e5-small","keep_alive":-1,"prompt":""}' 2>/dev/null && ok "Model pinned" || warn "Ollama not reachable"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LSFS Deployed — Super+Space to search    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "  lsfs-query --list-mode 'query'  → CLI search"
echo "  journalctl --user -u lsfs-daemon -f  → Live logs"
echo "  lsfs-parity  → Orphan cleanup,"
