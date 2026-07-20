#!/usr/bin/env bash
###############################################################################
# ultimate-fix-v2.sh — One-shot repair for Ash-ISO LSFS stack on Arch Linux
# Targets: Qdrant (standalone binary), LSFS Daemon (Python), Launcher Hook
# Prereqs: user pal, ~/ash-iso cloned, Ollama running w/ nomic-embed-text,
#          launcher hook at ~/.config/scripts/lsfs_launcher_hook.sh
###############################################################################
set -euo pipefail

# ── Globals ──────────────────────────────────────────────────────────────────
LOGFILE="/tmp/ultimate-v2-$(date +%Y%m%d-%H%M%S).log"
HOME_DIR="/home/pal"
USER_NAME="pal"
QDRANT_BIN="/usr/local/bin/qdrant"
QDRANT_DATA="/var/lib/qdrant"
QDRANT_SERVICE="/etc/systemd/system/qdrant.service"
DAEMON_SCRIPT="${HOME_DIR}/.config/scripts/lsfs_daemon.py"
DAEMON_SERVICE="${HOME_DIR}/.config/systemd/user/lsfs-daemon.service"
LAUNCHER_HOOK="${HOME_DIR}/.config/scripts/lsfs_launcher_hook.sh"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

PASS="${GREEN}✔${RESET}"
FAIL="${RED}✘${RESET}"

# ── Results accumulator for final table ──────────────────────────────────────
declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()

record_result() {
    local name="$1" ok="$2"
    CHECK_NAMES+=("$name")
    CHECK_RESULTS+=("$ok")
}

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*" | tee -a "$LOGFILE"; }
ok()   { echo -e "  ${PASS}  $*" | tee -a "$LOGFILE"; }
fail() { echo -e "  ${FAIL}  $*" | tee -a "$LOGFILE"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*" | tee -a "$LOGFILE"; }
banner() {
    echo "" | tee -a "$LOGFILE"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}" | tee -a "$LOGFILE"
    echo -e "${BOLD}  $*${RESET}" | tee -a "$LOGFILE"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}" | tee -a "$LOGFILE"
}

# Run a command; return 0 on success, 1 on failure — never exits the script.
try() {
    if "$@" >> "$LOGFILE" 2>&1; then
        return 0
    else
        return 1
    fi
}

wait_for_url() {
    local url="$1" retries="${2:-30}" delay="${3:-1}"
    local i
    for (( i=1; i<=retries; i++ )); do
        if curl -sf --max-time 2 "$url" > /dev/null 2>&1; then
            return 0
        fi
        sleep "$delay"
    done
    return 1
}

###############################################################################
# 1) FIX QDRANT
###############################################################################
fix_qdrant() {
    banner "STEP 1 — Fix Qdrant"

    # ── 1a. Download latest standalone binary ────────────────────────────────
    log "Determining latest Qdrant release from GitHub …"
    local qdrant_ok=true

    local latest_tag
    latest_tag=$(curl -sfL \
        "https://api.github.com/repos/qdrant/qdrant/releases/latest" \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/') || true

    if [[ -z "${latest_tag:-}" ]]; then
        warn "Could not determine latest tag; falling back to v1.13.6"
        latest_tag="v1.13.6"
    fi
    log "Using Qdrant ${latest_tag}"

    local download_url="https://github.com/qdrant/qdrant/releases/download/${latest_tag}/qdrant-x86_64-unknown-linux-musl.tar.gz"
    local tmp_tar="/tmp/qdrant-release.tar.gz"

    log "Downloading Qdrant binary …"
    if curl -fSL --progress-bar -o "$tmp_tar" "$download_url" 2>&1 | tee -a "$LOGFILE"; then
        ok "Downloaded ${download_url}"
    else
        # Try GNU variant
        download_url="https://github.com/qdrant/qdrant/releases/download/${latest_tag}/qdrant-x86_64-unknown-linux-gnu.tar.gz"
        log "Retrying with gnu variant …"
        if curl -fSL --progress-bar -o "$tmp_tar" "$download_url" 2>&1 | tee -a "$LOGFILE"; then
            ok "Downloaded (gnu variant)"
        else
            fail "Could not download Qdrant binary"
            qdrant_ok=false
        fi
    fi

    if $qdrant_ok; then
        log "Extracting and installing to ${QDRANT_BIN} …"
        local tmp_extract="/tmp/qdrant-extract-$$"
        mkdir -p "$tmp_extract"
        if tar -xzf "$tmp_tar" -C "$tmp_extract" 2>>"$LOGFILE"; then
            local found_bin
            found_bin=$(find "$tmp_extract" -type f -name "qdrant" | head -1)
            if [[ -n "$found_bin" ]]; then
                sudo install -m 0755 "$found_bin" "$QDRANT_BIN"
                ok "Installed ${QDRANT_BIN}"
            else
                fail "Binary 'qdrant' not found in tarball"
                qdrant_ok=false
            fi
        else
            fail "tar extraction failed"
            qdrant_ok=false
        fi
        rm -rf "$tmp_extract" "$tmp_tar" 2>/dev/null || true
    fi

    # ── 1b. System user + data directory ─────────────────────────────────────
    log "Ensuring system user 'qdrant' and data dir …"
    if ! id -u qdrant &>/dev/null; then
        if sudo useradd -r -s /usr/bin/nologin -d "$QDRANT_DATA" qdrant 2>>"$LOGFILE"; then
            ok "Created system user qdrant"
        else
            warn "Could not create user qdrant (may already exist in another form)"
        fi
    else
        ok "User qdrant already exists"
    fi

    sudo mkdir -p "$QDRANT_DATA"
    sudo chown -R qdrant:qdrant "$QDRANT_DATA" 2>>"$LOGFILE" || true
    ok "Data directory ${QDRANT_DATA} ready"

    # ── 1c. Systemd unit ─────────────────────────────────────────────────────
    log "Writing systemd service ${QDRANT_SERVICE} …"
    sudo tee "$QDRANT_SERVICE" > /dev/null <<'UNIT'
[Unit]
Description=Qdrant Vector Search Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=qdrant
Group=qdrant
ExecStart=/usr/local/bin/qdrant --storage-path /var/lib/qdrant
Restart=always
RestartSec=5
LimitNOFILE=65536
Environment="QDRANT__SERVICE__HTTP_PORT=6333"
Environment="QDRANT__SERVICE__GRPC_PORT=6334"

[Install]
WantedBy=multi-user.target
UNIT
    ok "Wrote ${QDRANT_SERVICE}"

    # ── 1d. Enable + start ───────────────────────────────────────────────────
    log "Reloading systemd and starting qdrant.service …"
    sudo systemctl daemon-reload 2>>"$LOGFILE"
    sudo systemctl enable qdrant.service 2>>"$LOGFILE" || true
    sudo systemctl restart qdrant.service 2>>"$LOGFILE" || true

    log "Waiting for Qdrant health check on :6333 …"
    if wait_for_url "http://localhost:6333/healthz" 30 1 || \
       wait_for_url "http://localhost:6333/health" 10 1 || \
       wait_for_url "http://localhost:6333" 5 1; then
        ok "Qdrant is healthy"
        record_result "Qdrant" "pass"
    else
        fail "Qdrant did not become healthy within 30 s"
        warn "Check: sudo journalctl -u qdrant.service --no-pager -n 30"
        record_result "Qdrant" "fail"
    fi
}

###############################################################################
# 2) FIX LSFS DAEMON
###############################################################################
fix_lsfs_daemon() {
    banner "STEP 2 — Fix LSFS Daemon"

    # ── 2a. Python dependencies ──────────────────────────────────────────────
    log "Installing Python packages …"
    if pip install --break-system-packages requests aiohttp inotify_simple 2>&1 | tee -a "$LOGFILE"; then
        ok "Python packages installed"
    else
        warn "pip install had issues — daemon may still work if packages were already present"
    fi

    # ── 2b. Embed the LSFS daemon Python script ─────────────────────────────
    log "Writing LSFS daemon to ${DAEMON_SCRIPT} …"
    mkdir -p "$(dirname "$DAEMON_SCRIPT")"

    cat > "$DAEMON_SCRIPT" << 'PYTHON_DAEMON'
#!/usr/bin/env python3
"""
lsfs_daemon.py — Lightweight Semantic Filesystem Daemon
Indexes files under /home/pal into Qdrant via Ollama nomic-embed-text embeddings.
Uses inotify for real-time updates with a polling fallback.
"""

import hashlib
import json
import logging
import mimetypes
import os
import signal
import sys
import time
import uuid
from pathlib import Path
from typing import Optional

import requests

# ── Configuration ────────────────────────────────────────────────────────────
WATCH_ROOT     = Path("/home/pal")
OLLAMA_URL     = "http://localhost:11434"
QDRANT_URL     = "http://localhost:6333"
COLLECTION     = "apps"
VECTOR_DIM     = 768
EMBED_MODEL    = "nomic-embed-text"
POLL_INTERVAL  = 60  # seconds — fallback if inotify unavailable
BATCH_SIZE     = 16
MAX_TEXT_BYTES  = 8192  # read at most this many bytes per file for embedding

SKIP_DIRS = {
    ".git", ".cache", ".local", ".cargo", ".rustup", ".npm", ".nvm",
    "__pycache__", "node_modules", ".venv", "venv", ".mozilla",
    ".thunderbird", ".steam", "snap", ".snapshots",
}
SKIP_EXTENSIONS = {
    ".o", ".so", ".a", ".pyc", ".pyo", ".class", ".jar",
    ".iso", ".img", ".qcow2", ".vmdk",
    ".mp4", ".mkv", ".avi", ".mov", ".flv",
    ".zip", ".tar", ".gz", ".bz2", ".xz", ".zst", ".7z", ".rar",
    ".bin", ".dat", ".db", ".sqlite", ".lock",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("lsfs")

# ── Qdrant helpers ───────────────────────────────────────────────────────────

def qdrant_ensure_collection() -> bool:
    """Create the collection if it doesn't exist. Return True on success."""
    try:
        r = requests.get(f"{QDRANT_URL}/collections/{COLLECTION}", timeout=5)
        if r.status_code == 200:
            log.info("Collection '%s' already exists.", COLLECTION)
            return True
    except requests.ConnectionError:
        log.error("Cannot reach Qdrant at %s", QDRANT_URL)
        return False

    payload = {
        "vectors": {
            "size": VECTOR_DIM,
            "distance": "Cosine",
        }
    }
    try:
        r = requests.put(
            f"{QDRANT_URL}/collections/{COLLECTION}",
            json=payload,
            timeout=10,
        )
        if r.status_code in (200, 201):
            log.info("Created collection '%s' (%d-dim Cosine).", COLLECTION, VECTOR_DIM)
            return True
        else:
            log.error("Failed to create collection: %s %s", r.status_code, r.text)
            return False
    except Exception as exc:
        log.error("Exception creating collection: %s", exc)
        return False


def qdrant_upsert(points: list[dict]) -> bool:
    """Upsert a batch of points into Qdrant."""
    if not points:
        return True
    try:
        r = requests.put(
            f"{QDRANT_URL}/collections/{COLLECTION}/points",
            json={"points": points},
            timeout=30,
        )
        return r.status_code in (200, 201)
    except Exception as exc:
        log.error("Qdrant upsert error: %s", exc)
        return False


# ── Ollama helpers ───────────────────────────────────────────────────────────

def embed_text(text: str) -> Optional[list[float]]:
    """Get embedding from Ollama. Returns vector or None."""
    if not text.strip():
        return None
    try:
        r = requests.post(
            f"{OLLAMA_URL}/api/embeddings",
            json={"model": EMBED_MODEL, "prompt": text},
            timeout=30,
        )
        if r.status_code == 200:
            data = r.json()
            return data.get("embedding")
        else:
            log.warning("Ollama embed returned %s", r.status_code)
            return None
    except Exception as exc:
        log.warning("Ollama embed error: %s", exc)
        return None


# ── File processing ──────────────────────────────────────────────────────────

def file_id(path: str) -> str:
    """Deterministic UUID from file path."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"file://{path}"))


def should_index(path: Path) -> bool:
    """Decide whether to index this path."""
    parts = set(path.parts)
    if parts & SKIP_DIRS:
        return False
    if path.suffix.lower() in SKIP_EXTENSIONS:
        return False
    if path.name.startswith("."):
        return False
    return True


def extract_text(path: Path) -> str:
    """Best-effort text extraction from a file."""
    mime, _ = mimetypes.guess_type(str(path))
    if mime and not mime.startswith("text") and mime not in (
        "application/json", "application/xml", "application/x-shellscript",
        "application/javascript", "application/x-yaml",
    ):
        # For non-text files, just embed the filename + path
        return f"File: {path.name}\nPath: {str(path)}"
    try:
        with open(path, "r", errors="replace") as fh:
            return fh.read(MAX_TEXT_BYTES)
    except Exception:
        return f"File: {path.name}\nPath: {str(path)}"


def process_file(path: Path) -> Optional[dict]:
    """Embed a single file and return a Qdrant point dict, or None."""
    try:
        stat = path.stat()
    except OSError:
        return None

    text = extract_text(path)
    prompt = f"search_document: {path.name}\n{text[:4096]}"
    vec = embed_text(prompt)
    if vec is None:
        return None

    return {
        "id": file_id(str(path)),
        "vector": vec,
        "payload": {
            "path": str(path),
            "name": path.name,
            "extension": path.suffix.lower(),
            "size": stat.st_size,
            "modified": stat.st_mtime,
            "text_preview": text[:512],
        },
    }


# ── Full walk ────────────────────────────────────────────────────────────────

def full_walk():
    """Walk WATCH_ROOT and index every eligible file."""
    log.info("Starting full filesystem walk of %s …", WATCH_ROOT)
    batch: list[dict] = []
    total_indexed = 0
    total_skipped = 0

    for dirpath, dirnames, filenames in os.walk(WATCH_ROOT):
        # Prune skipped directories in-place
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS and not d.startswith(".")
        ]
        for fname in filenames:
            fpath = Path(dirpath) / fname
            if not should_index(fpath):
                total_skipped += 1
                continue
            if not fpath.is_file():
                continue

            point = process_file(fpath)
            if point:
                batch.append(point)
                total_indexed += 1

            if len(batch) >= BATCH_SIZE:
                qdrant_upsert(batch)
                log.info("Indexed %d files so far …", total_indexed)
                batch.clear()

    if batch:
        qdrant_upsert(batch)

    log.info(
        "Full walk complete: %d indexed, %d skipped.", total_indexed, total_skipped
    )


# ── Inotify watcher ─────────────────────────────────────────────────────────

def run_inotify_watcher():
    """Watch for file changes via inotify and re-index changed files."""
    try:
        from inotify_simple import INotify, flags as iflags
    except ImportError:
        log.warning("inotify_simple not available — falling back to polling.")
        run_poll_watcher()
        return

    log.info("Starting inotify watcher on %s …", WATCH_ROOT)
    ino = INotify()
    watch_flags = (
        iflags.CREATE | iflags.MODIFY | iflags.MOVED_TO |
        iflags.DELETE | iflags.MOVED_FROM
    )

    wd_map: dict[int, Path] = {}

    def add_watches(root: Path):
        for dirpath, dirnames, _ in os.walk(root):
            dirnames[:] = [
                d for d in dirnames
                if d not in SKIP_DIRS and not d.startswith(".")
            ]
            dp = Path(dirpath)
            try:
                wd = ino.add_watch(str(dp), watch_flags)
                wd_map[wd] = dp
            except OSError:
                pass

    add_watches(WATCH_ROOT)
    log.info("Watching %d directories.", len(wd_map))

    while True:
        events = ino.read(timeout=POLL_INTERVAL * 1000)
        batch: list[dict] = []

        if not events:
            # Periodic heartbeat — could do a light re-check here
            continue

        for event in events:
            parent = wd_map.get(event.wd)
            if parent is None:
                continue
            fpath = parent / event.name
            if not should_index(fpath):
                continue

            if event.mask & (iflags.CREATE | iflags.MODIFY | iflags.MOVED_TO):
                if fpath.is_file():
                    point = process_file(fpath)
                    if point:
                        batch.append(point)
                        log.info("Re-indexed: %s", fpath)
                elif fpath.is_dir():
                    add_watches(fpath)

            elif event.mask & (iflags.DELETE | iflags.MOVED_FROM):
                fid = file_id(str(fpath))
                try:
                    requests.post(
                        f"{QDRANT_URL}/collections/{COLLECTION}/points/delete",
                        json={"points": [fid]},
                        timeout=5,
                    )
                    log.info("Deleted from index: %s", fpath)
                except Exception:
                    pass

        if batch:
            qdrant_upsert(batch)


def run_poll_watcher():
    """Simple polling fallback."""
    log.info("Starting poll-based watcher (interval=%ds) …", POLL_INTERVAL)
    while True:
        full_walk()
        time.sleep(POLL_INTERVAL)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT,  lambda *_: sys.exit(0))

    log.info("LSFS Daemon starting …")

    # Wait for Qdrant to be reachable (up to 60 s)
    for attempt in range(60):
        try:
            requests.get(f"{QDRANT_URL}/healthz", timeout=2)
            break
        except Exception:
            if attempt == 0:
                log.info("Waiting for Qdrant …")
            time.sleep(1)
    else:
        log.error("Qdrant not reachable after 60 s — exiting.")
        sys.exit(1)

    if not qdrant_ensure_collection():
        log.error("Could not ensure Qdrant collection — exiting.")
        sys.exit(1)

    # Wait for Ollama
    for attempt in range(30):
        try:
            requests.get(f"{OLLAMA_URL}/api/version", timeout=2)
            break
        except Exception:
            if attempt == 0:
                log.info("Waiting for Ollama …")
            time.sleep(1)
    else:
        log.error("Ollama not reachable after 30 s — exiting.")
        sys.exit(1)

    full_walk()
    run_inotify_watcher()


if __name__ == "__main__":
    main()
PYTHON_DAEMON

    chmod +x "$DAEMON_SCRIPT"
    ok "Wrote ${DAEMON_SCRIPT}"

    # ── 2c. Validate Python syntax ──────────────────────────────────────────
    log "Validating Python syntax …"
    if python3 -c "import py_compile; py_compile.compile('${DAEMON_SCRIPT}', doraise=True)" 2>&1 | tee -a "$LOGFILE"; then
        ok "Python syntax OK"
    else
        fail "Python syntax errors detected — review ${DAEMON_SCRIPT}"
        record_result "LSFS Daemon" "fail"
        return
    fi

    # ── 2d. Systemd user service ─────────────────────────────────────────────
    log "Writing systemd user service at ${DAEMON_SERVICE} …"
    mkdir -p "$(dirname "$DAEMON_SERVICE")"

    cat > "$DAEMON_SERVICE" << USERUNIT
[Unit]
Description=LSFS Semantic Filesystem Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${DAEMON_SCRIPT}
Restart=always
RestartSec=10
Environment="HOME=${HOME_DIR}"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
USERUNIT
    ok "Wrote ${DAEMON_SERVICE}"

    # ── 2e. Enable linger + start ────────────────────────────────────────────
    log "Enabling linger for user ${USER_NAME} …"
    if sudo loginctl enable-linger "$USER_NAME" 2>>"$LOGFILE"; then
        ok "Linger enabled for ${USER_NAME}"
    else
        warn "Could not enable linger (may need reboot)"
    fi

    log "Reloading user systemd and starting lsfs-daemon …"
    # Run as the target user
    if [[ "$(whoami)" == "$USER_NAME" ]]; then
        systemctl --user daemon-reload 2>>"$LOGFILE"
        systemctl --user enable lsfs-daemon.service 2>>"$LOGFILE" || true
        systemctl --user restart lsfs-daemon.service 2>>"$LOGFILE" || true
    else
        sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
            systemctl --user daemon-reload 2>>"$LOGFILE" || true
        sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
            systemctl --user enable lsfs-daemon.service 2>>"$LOGFILE" || true
        sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
            systemctl --user restart lsfs-daemon.service 2>>"$LOGFILE" || true
    fi

    sleep 3
    log "Checking daemon status …"
    local daemon_status
    if [[ "$(whoami)" == "$USER_NAME" ]]; then
        daemon_status=$(systemctl --user is-active lsfs-daemon.service 2>/dev/null || echo "unknown")
    else
        daemon_status=$(sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
            systemctl --user is-active lsfs-daemon.service 2>/dev/null || echo "unknown")
    fi

    if [[ "$daemon_status" == "active" || "$daemon_status" == "activating" ]]; then
        ok "lsfs-daemon.service is ${daemon_status}"
        record_result "LSFS Daemon" "pass"
    else
        fail "lsfs-daemon.service is ${daemon_status}"
        warn "Debug: systemctl --user status lsfs-daemon.service"
        warn "Debug: journalctl --user -u lsfs-daemon.service --no-pager -n 40"
        record_result "LSFS Daemon" "fail"
    fi
}

###############################################################################
# 3) VERIFY EVERYTHING
###############################################################################
verify_all() {
    banner "STEP 3 — Verification"

    # ── Qdrant ───────────────────────────────────────────────────────────────
    log "Checking Qdrant …"
    if curl -sf --max-time 3 "http://localhost:6333/healthz" > /dev/null 2>&1 || \
       curl -sf --max-time 3 "http://localhost:6333/health"  > /dev/null 2>&1 || \
       curl -sf --max-time 3 "http://localhost:6333"         > /dev/null 2>&1; then
        ok "Qdrant responding on :6333"
        # Only record if not already recorded
        local already=false
        for n in "${CHECK_NAMES[@]}"; do [[ "$n" == "Qdrant" ]] && already=true; done
        $already || record_result "Qdrant" "pass"
    else
        fail "Qdrant NOT responding"
        local already=false
        for n in "${CHECK_NAMES[@]}"; do [[ "$n" == "Qdrant" ]] && already=true; done
        $already || record_result "Qdrant" "fail"
    fi

    # ── Ollama ───────────────────────────────────────────────────────────────
    log "Checking Ollama …"
    if curl -sf --max-time 3 "http://localhost:11434/api/version" > /dev/null 2>&1; then
        ok "Ollama responding on :11434"
        # Verify model is available
        if curl -sf --max-time 5 "http://localhost:11434/api/tags" 2>/dev/null \
             | grep -q "nomic-embed-text"; then
            ok "Model nomic-embed-text is loaded"
        else
            warn "Model nomic-embed-text not found in Ollama tags"
        fi
        record_result "Ollama" "pass"
    else
        fail "Ollama NOT responding"
        record_result "Ollama" "fail"
    fi

    # ── LSFS Daemon ──────────────────────────────────────────────────────────
    log "Checking LSFS Daemon …"
    local daemon_status
    if [[ "$(whoami)" == "$USER_NAME" ]]; then
        daemon_status=$(systemctl --user is-active lsfs-daemon.service 2>/dev/null || echo "unknown")
    else
        daemon_status=$(sudo -u "$USER_NAME" XDG_RUNTIME_DIR="/run/user/$(id -u "$USER_NAME")" \
            systemctl --user is-active lsfs-daemon.service 2>/dev/null || echo "unknown")
    fi
    if [[ "$daemon_status" == "active" || "$daemon_status" == "activating" ]]; then
        ok "lsfs-daemon.service is ${daemon_status}"
        # Check if collection exists in Qdrant
        if curl -sf --max-time 3 "http://localhost:6333/collections/apps" > /dev/null 2>&1; then
            ok "Qdrant collection 'apps' exists"
        else
            warn "Qdrant collection 'apps' not yet created (daemon may still be starting)"
        fi
        # Don't re-record if already recorded from step 2
        local already=false
        for n in "${CHECK_NAMES[@]}"; do [[ "$n" == "LSFS Daemon" ]] && already=true; done
        $already || record_result "LSFS Daemon" "pass"
    else
        fail "lsfs-daemon.service is ${daemon_status}"
        local already=false
        for n in "${CHECK_NAMES[@]}"; do [[ "$n" == "LSFS Daemon" ]] && already=true; done
        $already || record_result "LSFS Daemon" "fail"
    fi

    # ── Launcher Hook ────────────────────────────────────────────────────────
    log "Checking launcher hook …"
    if [[ -x "$LAUNCHER_HOOK" ]]; then
        ok "Launcher hook exists and is executable: ${LAUNCHER_HOOK}"
        record_result "Launcher Hook" "pass"
    elif [[ -f "$LAUNCHER_HOOK" ]]; then
        warn "Launcher hook exists but is NOT executable — fixing …"
        chmod +x "$LAUNCHER_HOOK" 2>>"$LOGFILE" || true
        if [[ -x "$LAUNCHER_HOOK" ]]; then
            ok "Fixed permissions on ${LAUNCHER_HOOK}"
            record_result "Launcher Hook" "pass"
        else
            fail "Could not make launcher hook executable"
            record_result "Launcher Hook" "fail"
        fi
    else
        fail "Launcher hook NOT found at ${LAUNCHER_HOOK}"
        record_result "Launcher Hook" "fail"
    fi

    # ── Results table ────────────────────────────────────────────────────────
    echo "" | tee -a "$LOGFILE"
    banner "RESULTS"
    printf "  ${BOLD}%-25s  %-10s${RESET}\n" "Component" "Status" | tee -a "$LOGFILE"
    printf "  %-25s  %-10s\n"                 "─────────────────────────" "──────────" | tee -a "$LOGFILE"

    local all_pass=true
    for i in "${!CHECK_NAMES[@]}"; do
        local name="${CHECK_NAMES[$i]}"
        local result="${CHECK_RESULTS[$i]}"
        if [[ "$result" == "pass" ]]; then
            printf "  %-25s  ${GREEN}%-10s${RESET}\n" "$name" "✔ PASS" | tee -a "$LOGFILE"
        else
            printf "  %-25s  ${RED}%-10s${RESET}\n"   "$name" "✘ FAIL" | tee -a "$LOGFILE"
            all_pass=false
        fi
    done

    echo "" | tee -a "$LOGFILE"

    if $all_pass; then
        echo -e "${GREEN}${BOLD}All checks passed!${RESET}" | tee -a "$LOGFILE"
    else
        echo -e "${RED}${BOLD}Some checks failed — review the output above.${RESET}" | tee -a "$LOGFILE"
    fi

    echo "" | tee -a "$LOGFILE"
    echo -e "${BOLD}Log file:${RESET} ${LOGFILE}" | tee -a "$LOGFILE"

    # ── User instructions ────────────────────────────────────────────────────
    echo "" | tee -a "$LOGFILE"
    banner "NEXT STEPS"
    cat <<'EOF' | tee -a "$LOGFILE"
  Your LSFS stack is configured. To use the semantic launcher:

    1. Press  Super + Space  to open the launcher
    2. Start typing a natural-language query (e.g. "my resume" or "shell scripts")
    3. The launcher hook queries Qdrant via Ollama embeddings and returns
       matching files ranked by semantic similarity.

  Useful commands:
    • sudo systemctl status qdrant          — Qdrant service status
    • systemctl --user status lsfs-daemon   — Daemon status
    • journalctl --user -u lsfs-daemon -f   — Daemon live logs
    • curl localhost:6333/collections/apps   — Qdrant collection info
EOF
    echo "" | tee -a "$LOGFILE"
}

###############################################################################
# MAIN
###############################################################################
main() {
    echo -e "${BOLD}ultimate-fix-v2.sh${RESET} — $(date)" | tee -a "$LOGFILE"
    echo -e "Logging to ${CYAN}${LOGFILE}${RESET}" | tee -a "$LOGFILE"

    # Sanity: must be root or have sudo
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -v 2>/dev/null; then
            echo -e "${FAIL} This script requires sudo privileges." | tee -a "$LOGFILE"
            exit 1
        fi
    fi

    fix_qdrant
    fix_lsfs_daemon
    verify_all
}

main "$@"
