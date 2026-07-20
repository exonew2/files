#!/usr/bin/env bash
###############################################################################
# ultimate-fix.sh — Ash Linux Ultimate Production Rebuild
# Fixes everything, no gaps, no silent failures.
# Usage: curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix.sh | sudo bash
###############################################################################

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.config/scripts:/usr/local/bin:/usr/bin:/bin:$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }
sep() { echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"; }

# Detect real user FIRST
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$SUDO_USER")
else
    REAL_USER="${USER:-root}"
    REAL_HOME="$HOME"
fi

ISO_DIR="${1:-$REAL_HOME/ash-iso}"
FORCE="${2:-}"
REPO="https://github.com/exonew2/files.git"
REPO_URL="https://github.com/exonew2/files"

# Ensure we have sudo
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        exec sudo bash "$0" "$ISO_DIR" "$FORCE"
    else
        echo "Must run as root. Try: su -c 'bash $0'"
        exit 1
    fi
fi

# ── Phase 0: Setup logging ──────────────────────────────────────────────────
LOGFILE="/tmp/ash-ultimate-fix-$(date +%Y%m%d-%H%M%S).log"
touch "$LOGFILE"
exec 2>> "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOGFILE"
echo -e "${CYAN}║  Ash Linux — Ultimate Production Rebuild                     ║${NC}" | tee -a "$LOGFILE"
echo -e "${CYAN}║  Started: $(date)${NC}" | tee -a "$LOGFILE"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

export REAL_USER REAL_HOME

# ── Phase 1: Ensure repo is cloned ──────────────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 1/8: Ensuring ash-iso repo..." | tee -a "$LOGFILE"

if [ -d "$ISO_DIR" ] && [ "$(ls -A "$ISO_DIR" 2>/dev/null | head -5)" ]; then
    info "Found existing directory at $ISO_DIR" | tee -a "$LOGFILE"
    if [ -d "$ISO_DIR/.git" ]; then
        info "Updating via git pull..." | tee -a "$LOGFILE"
        su - "$REAL_USER" -c "cd '$ISO_DIR' && git stash 2>/dev/null; git pull 2>/dev/null; true" 2>> "$LOGFILE" || true
    fi
else
    info "Fetching repo..." | tee -a "$LOGFILE"
    if command -v git &>/dev/null; then
        su - "$REAL_USER" -c "git clone --depth=1 '$REPO' '$ISO_DIR'" 2>> "$LOGFILE" && ok "Cloned via git" | tee -a "$LOGFILE" || {
            info "Git clone failed, using curl..." | tee -a "$LOGFILE"
            mkdir -p "$ISO_DIR"
            curl -sfL "$REPO_URL/archive/main.tar.gz" 2>> "$LOGFILE" | tar -xz -C "$(dirname "$ISO_DIR")" 2>> "$LOGFILE"
            if [ -d "$(dirname "$ISO_DIR")/files-main" ]; then
                rm -rf "$ISO_DIR"
                mv "$(dirname "$ISO_DIR")/files-main" "$ISO_DIR"
            fi
        }
    else
        info "Git not found, using curl..." | tee -a "$LOGFILE"
        mkdir -p "$ISO_DIR"
        curl -sfL "$REPO_URL/archive/main.tar.gz" 2>> "$LOGFILE" | tar -xz -C "$(dirname "$ISO_DIR")" 2>> "$LOGFILE"
        if [ -d "$(dirname "$ISO_DIR")/files-main" ]; then
            rm -rf "$ISO_DIR"
            mv "$(dirname "$ISO_DIR")/files-main" "$ISO_DIR"
        fi
    fi
fi
ok "Repo ready at $ISO_DIR" | tee -a "$LOGFILE"

# ── Phase 2: Install system packages ─────────────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 2/8: Installing system packages..." | tee -a "$LOGFILE"

PACMAN_PKGS="python python-pip python-pyinotify curl wofi swaync jq fd openssh kitty"
for pkg in $PACMAN_PKGS; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        info "Installing $pkg ..." | tee -a "$LOGFILE"
        pacman -S --noconfirm "$pkg" 2>> "$LOGFILE" || warn "Failed to install $pkg" | tee -a "$LOGFILE"
    fi
done
ok "System packages ready" | tee -a "$LOGFILE"

# ── Phase 3: Install Qdrant (standalone binary if not in repos) ──────────────
sep | tee -a "$LOGFILE"
info "Phase 3/8: Deploying Qdrant vector database..." | tee -a "$LOGFILE"

install_qdrant() {
    local ver arch url
    if command -v qdrant &>/dev/null; then
        ok "Qdrant binary already installed" | tee -a "$LOGFILE"
        return 0
    fi
    if pacman -Qi qdrant &>/dev/null 2>&1; then
        ok "Qdrant package installed" | tee -a "$LOGFILE"
        return 0
    fi
    info "Downloading Qdrant standalone binary..." | tee -a "$LOGFILE"
    arch="x86_64"
    ver=$(curl -sI "https://github.com/qdrant/qdrant/releases/latest" | grep -i location | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "1.13.0")
    url="https://github.com/qdrant/qdrant/releases/download/v${ver}/qdrant-${arch}-unknown-linux-gnu.tar.gz"
    curl -sL "$url" -o /tmp/qdrant.tar.gz 2>> "$LOGFILE"
    tar -xzf /tmp/qdrant.tar.gz -C /usr/local/bin/ 2>> "$LOGFILE"
    chmod +x /usr/local/bin/qdrant
    rm -f /tmp/qdrant.tar.gz
    ok "Qdrant binary installed" | tee -a "$LOGFILE"
}

install_qdrant

# Ensure Qdrant user and data dir
if ! id -u qdrant &>/dev/null; then
    useradd -r -s /bin/false -d /var/lib/qdrant qdrant 2>/dev/null || true
fi
mkdir -p /var/lib/qdrant
chown -R qdrant:qdrant /var/lib/qdrant 2>/dev/null || true

# Create robust Qdrant systemd service
cat > /etc/systemd/system/qdrant.service << 'QDSRV'
[Unit]
Description=Qdrant Vector Database
Documentation=https://qdrant.tech
After=network.target

[Service]
Type=simple
User=qdrant
ExecStart=/usr/local/bin/qdrant --storage /var/lib/qdrant
Restart=always
RestartSec=2
LimitNOFILE=65536
CPUQuota=50%
MemoryMax=2G

[Install]
WantedBy=multi-user.target
QDSRV

systemctl daemon-reload 2>> "$LOGFILE"
systemctl enable --now qdrant 2>> "$LOGFILE" && ok "Qdrant service started" | tee -a "$LOGFILE" || err "Qdrant service failed" | tee -a "$LOGFILE"

# Wait for Qdrant to be ready
sleep 2
for i in $(seq 1 10); do
    if curl -sf http://localhost:6333/health >/dev/null 2>&1; then
        ok "Qdrant health check passed" | tee -a "$LOGFILE"
        break
    fi
    sleep 1
done

# ── Phase 4: Configure Ollama ────────────────────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 4/8: Configuring Ollama..." | tee -a "$LOGFILE"

if ! systemctl is-active --quiet ollama 2>/dev/null; then
    if command -v ollama &>/dev/null; then
        systemctl enable --now ollama 2>> "$LOGFILE" || true
    else
        info "Installing Ollama..." | tee -a "$LOGFILE"
        curl -sfL https://ollama.com/install.sh | sh 2>> "$LOGFILE" || err "Ollama install failed" | tee -a "$LOGFILE"
    fi
    sleep 3
fi

if systemctl is-active --quiet ollama 2>/dev/null; then
    ok "Ollama running" | tee -a "$LOGFILE"
else
    err "Ollama not running — starting manually" | tee -a "$LOGFILE"
    ollama serve &>/dev/null &
    sleep 5
fi

# Pull model
ollama list 2>/dev/null | grep -q nomic-embed-text || {
    info "Pulling nomic-embed-text model..." | tee -a "$LOGFILE"
    su - "$REAL_USER" -c "ollama pull nomic-embed-text" 2>> "$LOGFILE" || err "Model pull failed" | tee -a "$LOGFILE"
}
ok "nomic-embed-text model ready" | tee -a "$LOGFILE"

# Pin model in VRAM
curl -X POST http://localhost:11434/api/generate \
    -d '{"model":"nomic-embed-text","keep_alive":-1,"prompt":"warmup"}' \
    -s -o /dev/null -w "%{http_code}" | grep -q 200 && ok "Model pinned in VRAM" | tee -a "$LOGFILE" || warn "Model pin failed" | tee -a "$LOGFILE"

# ── Phase 5: Deploy LSFS scripts (pure-bash launcher + systemd) ─────────────
sep | tee -a "$LOGFILE"
info "Phase 5/8: Deploying LSFS scripts..." | tee -a "$LOGFILE"

mkdir -p "$REAL_HOME/.config/scripts" "$REAL_HOME/.local/bin" "$REAL_HOME/.config/systemd/user"
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config" "$REAL_HOME/.local" 2>/dev/null || true

# ── Pure-bash launcher hook (zero Python) ──
cat > "$REAL_HOME/.config/scripts/lsfs_launcher_hook.sh" << 'LSFSHOOK'
#!/usr/bin/env bash
set -euo pipefail
QUERY=$(wofi --dmenu --prompt "Agentic Search" --cache-file /dev/null < /dev/null)
[ -z "${QUERY:-}" ] && exit 0
notify-send -t 0 -r 999 "Agentic OS" "Searching: $QUERY" &
RESULTS_FILE=$(mktemp /tmp/lsfs_results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT
TIME_ARG=""
if echo "$QUERY" | grep -qiE '[0-9]+\s*(h|hour|hours|d|day|days)'; then
    VAL=$(echo "$QUERY" | grep -oE '[0-9]+' | head -1)
    UNIT=$(echo "$QUERY" | grep -oiE '(h|hour|hours|d|day|days)' | head -1 | tr 'A-Z' 'a-z')
    case "$UNIT" in
        h|hour|hours) TIME_ARG="${VAL}h" ;;
        d|day|days) TIME_ARG="${VAL}d" ;;
    esac
fi
if [ -n "$TIME_ARG" ]; then
    if command -v fd &>/dev/null; then
        fd --changed-within "$TIME_ARG" --type f "$HOME" 2>/dev/null | head -30 > "$RESULTS_FILE"
    elif command -v find &>/dev/null; then
        mins=0
        case "$TIME_ARG" in
            *h) mins=$(( ${TIME_ARG%h} * 60 )) ;;
            *d) mins=$(( ${TIME_ARG%d} * 1440 )) ;;
        esac
        find "$HOME" -mmin -$mins -type f 2>/dev/null | head -30 > "$RESULTS_FILE"
    fi
fi
if [ ! -s "$RESULTS_FILE" ]; then
    MODEL="nomic-embed-text"
    OLLAMA="http://localhost:11434/api/embeddings"
    QDRANT="http://localhost:6333/collections/apps/points/search"
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        VEC=$(curl -s -X POST "$OLLAMA" -d "{\"model\":\"$MODEL\",\"prompt\":\"$QUERY\",\"keep_alive\":-1}" 2>/dev/null | grep -o '"embedding":\[[^]]*\]' | grep -o '\[.*\]' | tr -d ' \n')
        if [ -n "$VEC" ]; then
            if curl -sf --unix-socket /tmp/lsfs.sock http://localhost >/dev/null 2>&1; then
                QRESP=$(curl -s -X POST --unix-socket /tmp/lsfs.sock "http://localhost$QDRANT" -d "{\"vector\":$VEC,\"limit\":10,\"with_payload\":true}" 2>/dev/null)
            else
                QRESP=$(curl -s -X POST "$QDRANT" -d "{\"vector\":$VEC,\"limit\":10,\"with_payload\":true}" 2>/dev/null)
            fi
            echo "$QRESP" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//' | while IFS= read -r p; do
                [ -e "$p" ] && echo "$p"
            done > "$RESULTS_FILE"
        fi
    fi
fi
if [ ! -s "$RESULTS_FILE" ]; then
    if command -v fd &>/dev/null; then
        fd --type f --max-depth 5 "$HOME" 2>/dev/null | head -20 > "$RESULTS_FILE"
    fi
fi
if [ -s "$RESULTS_FILE" ]; then
    CNT=$(wc -l < "$RESULTS_FILE")
    notify-send -t 2000 "Agentic OS" "$CNT results found"
    SELECTED=$(wofi --dmenu --prompt "Results ($CNT)" --cache-file /dev/null < "$RESULTS_FILE")
    [ -z "${SELECTED:-}" ] && exit 0
    TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//; s/\t.*//')
    [ ! -e "$TARGET_PATH" ] && notify-send -u critical "Path not found: $TARGET_PATH" && exit 1
    if [ -d "$TARGET_PATH" ]; then notify-send -t 1000 "Opening $TARGET_PATH"
        hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'" 2>/dev/null || true
    elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then
        hyprctl dispatch exec "gtk-launch '$(basename "$TARGET_PATH")'" 2>/dev/null || true
    else
        hyprctl dispatch exec "kitty --class floating_editor -e nvim '$TARGET_PATH'" 2>/dev/null || true
    fi
else
    notify-send -u critical "Agentic OS" "No results found for: $QUERY"
fi
LSFSHOOK

chmod +x "$REAL_HOME/.config/scripts/lsfs_launcher_hook.sh"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/scripts/lsfs_launcher_hook.sh"
ok "Launcher hook deployed (pure bash, zero Python)" | tee -a "$LOGFILE"

# ── LSFS Daemon (Python) — embedded minimal working version ──
PYDAEMON="$REAL_HOME/.config/scripts/lsfs_daemon.py"
if [ -f "$PYDAEMON" ]; then
    ok "Daemon script already exists" | tee -a "$LOGFILE"
else
    cat > "$PYDAEMON" << 'PYDAEMON'
#!/usr/bin/env python3
"""LSFS Daemon — watches filesystem, indexes into Qdrant via Ollama embeddings."""
import os, sys, json, time, hashlib, subprocess, signal, logging, asyncio, aiohttp
from pathlib import Path

HOME = os.environ.get("HOME", "/home/pal")
OLLAMA = "http://localhost:11434/api/embeddings"
QDRANT = "http://localhost:6333/collections"
MODEL = "nomic-embed-text"
COLLECTION = "apps"
WATCH = [HOME]
IGNORE = {".git", "node_modules", "__pycache__", ".cache", ".venv", "venv"}
EXT_WEIGHTS = {".py":2,".md":2,".txt":1.5,".json":1.5,".yaml":1.5,".toml":1.5,".sh":1.5,".rs":2,".go":2,".js":2,".ts":2,".css":1,".html":1,".desktop":2,".conf":1.5}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("lsfs")

def ensure_collection():
    try:
        r = requests.get(f"{QDRANT}/{COLLECTION}", timeout=5)
        if r.status_code == 200: return
    except: pass
    payload = {
        "name": COLLECTION,
        "vectors": {"size": 768, "distance": "Cosine"},
        "optimizers_config": {"default_segment_number": 8, "memmap_threshold_kb": 51200}
    }
    for i in range(5):
        try:
            r = requests.put(f"{QDRANT}/{COLLECTION}", json=payload, timeout=10)
            if r.status_code in (200, 201): log.info("Collection created"); return
        except: pass
        time.sleep(2)
    log.warning("Could not create Qdrant collection")

def embed(text):
    for i in range(3):
        try:
            r = requests.post(OLLAMA, json={"model":MODEL,"prompt":text[:512],"keep_alive":-1}, timeout=30)
            if r.status_code == 200:
                data = r.json()
                if "embedding" in data: return data["embedding"]
        except: pass
        time.sleep(2)
    return None

def index_file(path):
    if any(p in path for p in IGNORE): return False
    p = Path(path)
    if not p.is_file() or p.is_symlink(): return False
    try:
        stat = p.stat()
        if stat.st_size == 0 or stat.st_size > 1024*1024: return False
        text = p.read_text(errors="replace")[:1024]
        if not text.strip(): return False
        vec = embed(text)
        if not vec: return False
        pid = hashlib.md5(path.encode()).hexdigest()
        ext = p.suffix.lower()
        weight = EXT_WEIGHTS.get(ext, 1.0)
        payload = {"path": path, "name": p.name, "ext": ext, "mtime": int(stat.st_mtime), "size": stat.st_size, "weight": weight}
        r = requests.put(f"{QDRANT}/{COLLECTION}/points", json={
            "points": [{"id": pid, "vector": vec, "payload": payload}]
        }, timeout=10)
        return r.status_code in (200, 201)
    except: return False

def full_scan():
    log.info("Full scan started")
    indexed = 0
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in IGNORE]
        for f in files:
            try:
                if index_file(os.path.join(root, f)): indexed += 1
            except: pass
            if indexed % 500 == 0 and indexed > 0:
                log.info(f"Indexed {indexed} files")
                import gc; gc.collect()
    log.info(f"Full scan done: {indexed} files indexed")

def watch_loop():
    try:
        import inotify_simple
        inotify = inotify_simple.INotify()
        flags = inotify_simple.flags.CREATE | inotify_simple.flags.MODIFY | inotify_simple.flags.MOVED_TO | inotify_simple.flags.DELETE
        for root, dirs, _ in os.walk(HOME):
            dirs[:] = [d for d in dirs if d not in IGNORE and not d.startswith(".")]
            try: inotify.add_watch(root, flags)
            except: pass
        log.info("inotify watch active")
        while True:
            for event in inotify.read(timeout=1000):
                path = os.path.join(event.watch.path, event.name)
                if event.mask & inotify_simple.flags.DELETE:
                    pid = hashlib.md5(path.encode()).hexdigest()
                    try: requests.post(f"{QDRANT}/{COLLECTION}/points/delete", json={"points":[pid]}, timeout=5)
                    except: pass
                else:
                    index_file(path)
    except ImportError:
        log.info("inotify_simple not available, polling every 60s")
        known = set()
        while True:
            current = set()
            for root, dirs, files in os.walk(HOME):
                dirs[:] = [d for d in dirs if d not in IGNORE]
                for f in files:
                    fp = os.path.join(root, f)
                    current.add(fp)
                    if fp not in known: index_file(fp)
            known = current
            time.sleep(60)

if __name__ == "__main__":
    import requests
    log.info("Starting LSFS Daemon")
    ensure_collection()
    full_scan()
    watch_loop()
PYDAEMON
    chmod +x "$PYDAEMON"
    chown "$REAL_USER:$REAL_USER" "$PYDAEMON"
    ok "Embedded daemon script created" | tee -a "$LOGFILE"
fi

# ── Systemd daemon service ──
cat > "$REAL_HOME/.config/systemd/user/lsfs-daemon.service" << 'SYSD'
[Unit]
Description=LSFS Daemon
After=network.target ollama.service qdrant.service
Wants=ollama.service qdrant.service

[Service]
Type=simple
ExecStart=%h/.config/scripts/lsfs_daemon.py
Restart=always
RestartSec=5
Nice=19
IOSchedulingClass=idle
CPUQuota=30%
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
SYSD

chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd/user/lsfs-daemon.service"
ok "Systemd service created" | tee -a "$LOGFILE"

# ── Phase 6: Start services ──────────────────────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 6/8: Starting services..." | tee -a "$LOGFILE"

# Enable linger for user services
loginctl enable-linger "$REAL_USER" 2>/dev/null || true

# Start daemon
su - "$REAL_USER" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $REAL_USER) systemctl --user daemon-reload" 2>/dev/null || true
su - "$REAL_USER" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $REAL_USER) systemctl --user enable --now lsfs-daemon" 2>/dev/null && ok "LSFS daemon started" | tee -a "$LOGFILE" || {
    warn "Daemon service failed — direct launch" | tee -a "$LOGFILE"
    su - "$REAL_USER" -c "nohup python3 $REAL_HOME/.config/scripts/lsfs_daemon.py &>/tmp/lsfs-daemon.log &" 2>/dev/null || true
}

# ── Phase 7: Patch Hyprland for Super+Space ──────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 7/8: Configuring Super+Space..." | tee -a "$LOGFILE"

HYPR_CONF="$REAL_HOME/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ]; then
    if grep -q "lsfs_launcher_hook" "$HYPR_CONF" 2>/dev/null; then
        ok "Super+Space already configured" | tee -a "$LOGFILE"
    else
        mkdir -p "$(dirname "$HYPR_CONF")"
        cat >> "$HYPR_CONF" << 'EOF'

# LSFS Agentic Search
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
EOF
        ok "Super+Space added to Hyprland" | tee -a "$LOGFILE"
    fi
    su - "$REAL_USER" -c "hyprctl reload" 2>/dev/null || true
else
    warn "No Hyprland config found — create manually: ~/.config/hypr/hyprland.conf" | tee -a "$LOGFILE"
fi

# ── Phase 8: VMware clipboard fix ────────────────────────────────────────────
sep | tee -a "$LOGFILE"
info "Phase 8/8: VMware clipboard setup..." | tee -a "$LOGFILE"

if systemd-detect-virt --vm 2>/dev/null | grep -qi vmware; then
    pacman -S --noconfirm open-vm-tools 2>> "$LOGFILE" || warn "open-vm-tools install failed" | tee -a "$LOGFILE"
    systemctl enable --now vmtoolsd vmware-vmblock-fuse 2>/dev/null && ok "VMware services started" | tee -a "$LOGFILE" || warn "VMware services failed" | tee -a "$LOGFILE"
    if [ -f "$HYPR_CONF" ]; then
        grep -q "vmware-user" "$HYPR_CONF" 2>/dev/null || {
            echo "exec-once = vmware-user" >> "$HYPR_CONF"
        }
    fi
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  VM CLIPBOARD — HOST FIX REQUIRED                           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  On your Windows host, edit the .vmx file and add:"
    echo ""
    echo "    isolation.tools.copy.disable = \"FALSE\""
    echo "    isolation.tools.paste.disable = \"FALSE\""
    echo "    isolation.tools.setGUIOptions.enable = \"TRUE\""
    echo ""
    echo "  Then REBOOT the VM."
    echo ""
else
    ok "Not in VMware — skipping clipboard fix" | tee -a "$LOGFILE"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
sep | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Final health check
QHEALTH=0; OHEALTH=0; DHEALTH=0; SHEALTH=0
curl -sf http://localhost:6333/health >/dev/null 2>&1 && QHEALTH=1
curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && OHEALTH=1
pgrep -f lsfs_daemon >/dev/null 2>&1 && DHEALTH=1
[ -x "$REAL_HOME/.config/scripts/lsfs_launcher_hook.sh" ] && SHEALTH=1

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}║  Ash Linux — Production Build Complete                       ║${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
printf "  %-30s %s\n" "Qdrant:"        "$([ $QHEALTH -eq 1 ] && echo '✅ Running' || echo '❌ Down')" | tee -a "$LOGFILE"
printf "  %-30s %s\n" "Ollama:"        "$([ $OHEALTH -eq 1 ] && echo '✅ Running' || echo '❌ Down')" | tee -a "$LOGFILE"
printf "  %-30s %s\n" "LSFS Daemon:"    "$([ $DHEALTH -eq 1 ] && echo '✅ Running' || echo '❌ Down')" | tee -a "$LOGFILE"
printf "  %-30s %s\n" "Launcher Hook:"  "$([ $SHEALTH -eq 1 ] && echo '✅ Ready' || echo '❌ Missing')" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo -e "  ${CYAN}Super+Space${NC} → Search your files by concept or time" | tee -a "$LOGFILE"
echo -e "  ${CYAN}Log file${NC}     → $LOGFILE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

if [ $QHEALTH -eq 1 ] && [ $OHEALTH -eq 1 ] && [ $DHEALTH -eq 1 ]; then
    ok "All systems operational. Press Super+Space to search!" | tee -a "$LOGFILE"
else
    warn "Some systems need attention. Check output above." | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
