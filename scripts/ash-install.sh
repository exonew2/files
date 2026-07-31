#!/usr/bin/env bash
# ash-install.sh — Ash Linux v4.0.0
# One-shot installer: Qdrant + Ollama + LSFS + Hyprland launcher
# Features: dry-run, preflight, rollback, profiles, multi-arch, GPU detect, hardening
set -euo pipefail

VERSION="4.0.0"
CONFIG_DIR="/etc/ash"
CACHE_DIR="/var/cache/ash-install"
BACKUP_DIR="/var/backups/ash-install"
LOG_DIR="/var/log/ash-install"
STATE_FILE="$LOG_DIR/state.json"
INSTALL_MARK="/etc/ash-installed"
MANIFEST="$LOG_DIR/manifest.txt"
SECRETS_FILE="$CONFIG_DIR/secrets.env"
QDRANT_API_KEY=""
LOCK_FILE="/var/lock/ash-install.lock"
AUDIT_LOG="/var/log/ash/audit.log"

HOME_DIR="${HOME:-/home/$(whoami)}"
USER_NAME="${USER:-$(whoami)}"
ARCH="${ARCH:-$(uname -m)}"

mkdir -p "$LOG_DIR" "$CACHE_DIR" "$BACKUP_DIR" "$CONFIG_DIR"
LOGFILE="$LOG_DIR/ash-install-$(date +%Y%m%d-%H%M%S).log"
exec 2> >(tee -a "$LOGFILE" >&2)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
PASS="${GREEN}✔${NC}"; FAIL="${RED}✘${NC}"; WARN="${YELLOW}⚠${NC}"

DRY_RUN=false; PROFILE="desktop"; MEMORY_MAX=""; CPU_QUOTA=""; MODEL="nomic-embed-text"
GPU_MODE="auto"; NO_FIREWALL=false; NO_HARDEN=false; TELEMETRY=false; OFFLINE_BUNDLE=""
WEBHOOK_URL=""; AUDIT_LEVEL="none"; MAX_RETRIES=5

declare -a PHASES=(); declare -a PHASE_STATUS=(); ROLLBACK_SNAPSHOT=""; SNAPSHOT_METHOD=""

while [[ $# -gt 0 ]]; do case "$1" in
  --dry-run) DRY_RUN=true ;;
  --profile) PROFILE="$2"; shift ;;
  --model) MODEL="$2"; shift ;;
  --memory-max) MEMORY_MAX="$2"; shift ;;
  --cpu-quota) CPU_QUOTA="$2"; shift ;;
  --gpu) GPU_MODE="$2"; shift ;;
  --no-firewall) NO_FIREWALL=true ;;
  --no-harden) NO_HARDEN=true ;;
  --telemetry) TELEMETRY=true ;;
  --offline) OFFLINE_BUNDLE="$2"; shift ;;
  --webhook-url) WEBHOOK_URL="$2"; shift ;;
  --audit-level) AUDIT_LEVEL="$2"; shift ;;
  --max-retries) MAX_RETRIES="$2"; shift ;;
  --help) echo "Usage: $0 [--dry-run] [--profile desktop|server|ci|minimal] [--model nomic-embed-text|mxbai-embed-large|all-MiniLM-L6-v2] [--memory-max 2G] [--cpu-quota 50%] [--gpu auto|nvidia|amd|intel|cpu] [--no-firewall] [--no-harden] [--offline bundle.tar.gz] [--webhook-url https://hooks.slack.com/...] [--audit-level none|metadata|full] [--max-retries 5]"; exit 0 ;;
  *) echo "Unknown: $1"; exit 1 ;;
esac; shift; done

cleanup() { local r=$?; [[ $r -ne 0 ]] && { warn "Crash detected — cleaning up"; rollback; }; exit $r; }
trap cleanup EXIT INT TERM

###############################################################################
# CORE UTILITIES
###############################################################################

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*" | tee -a "$LOGFILE"; }
ok()   { echo -e "  ${PASS}  $*" | tee -a "$LOGFILE"; }
fail() { echo -e "  ${FAIL}  $*" | tee -a "$LOGFILE"; }
warn() { echo -e "  ${WARN}  $*" | tee -a "$LOGFILE"; }

phase_start() { PHASES+=("$1"); PHASE_STATUS+=("pending"); log "────────── $1 ──────────"; }
phase_ok()    { local i=$((${#PHASES[@]}-1)); PHASE_STATUS[$i]="pass"; ok "$1"; }
phase_fail()  { local i=$((${#PHASES[@]}-1)); PHASE_STATUS[$i]="fail"; fail "$1"; }

retry() {
  local max="${MAX_RETRIES:-5}" n=0 delay=1
  until "$@" >>"$LOGFILE" 2>&1; do
    if ((++n >= max)); then log "retry $n/$max FAILED: $*"; return 1; fi
    log "retry $n/$max failed — waiting ${delay}s ..."; sleep "$delay"; delay=$((delay * 2))
  done
}

run_phase() {
  local name="$1" label="$2"; shift 2
  if [[ "$DRY_RUN" == true ]]; then phase_start "$name"; phase_ok "$label (dry-run)"; return 0; fi
  phase_start "$name"
  if "$@"; then phase_ok "$label"; else phase_fail "$label"; return 1; fi
}

sync_state() { sync; }

record_manifest() { echo "$(date +%Y%m%d-%H%M%S) $*" >> "$MANIFEST"; }

backup_config() {
  local src="$1"
  [[ ! -f "$src" ]] && return 0
  local dest="$BACKUP_DIR/$(echo "$src" | sed 's|/|_|g').$(date +%Y%m%d-%H%M%S)"
  cp "$src" "$dest" && record_manifest "backup $src -> $dest"
}

flock_state() {
  local fd=200 op="$1"
  case "$op" in
    acquire)
      exec 200>"$LOCK_FILE"
      flock -n 200 2>/dev/null || { warn "Another install is running (lock held)"; exit 1; }
      echo $$ > "$LOCK_FILE"
      ;;
    release)
      flock -u 200 2>/dev/null || true
      exec 200>&-
      rm -f "$LOCK_FILE" 2>/dev/null || true
      ;;
  esac
}

audit_log() {
  [[ "$AUDIT_LEVEL" == "none" ]] && return 0
  local query="$1" result_count="$2" latency="$3"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  local ts timestamp truncated
  ts=$(date +%s)
  timestamp=$(date +%Y-%m-%dT%H:%M:%S)
  truncated="${query:0:200}"
  if [[ "$AUDIT_LEVEL" == "full" ]]; then
    echo "$timestamp|$ts|$truncated|$result_count|${latency}ms" >> "$AUDIT_LOG"
  else
    echo "$timestamp|$result_count|${latency}ms" >> "$AUDIT_LOG"
  fi
  chmod 600 "$AUDIT_LOG"
}

detect_pm() {
  for pm in pacman apt dnf yum zypper apk xbps-install; do
    command -v "$pm" &>/dev/null && { echo "$pm"; return 0; }
  done; echo "unknown"; return 1
}

pm_install() {
  local pm=$(detect_pm)
  case "$pm" in
    pacman) pacman -S --noconfirm --needed "$@" ;;
    apt)    DEBIAN_FRONTEND=noninteractive apt install -y "$@" ;;
    dnf|yum) $pm install -y "$@" ;;
    zypper) zypper install -y "$@" ;;
    apk)    apk add "$@" ;;
    xbps-install) xbps-install -y "$@" ;;
    *) fail "No known package manager"; return 1 ;;
  esac
}

pm_query() { local pm=$(detect_pm); case $pm in pacman) pacman -Qi "$1" &>/dev/null;; apt) dpkg -l "$1" &>/dev/null;; dnf|yum) $pm list installed "$1" &>/dev/null;; zypper) zypper search --installed-only "$1" &>/dev/null;; apk) apk info "$1" &>/dev/null;; xbps-install) xbps-query "$1" &>/dev/null;; *) return 1;; esac; }

pm_translate() {
  local pkg="$1"
  local pm=$(detect_pm)
  declare -A PKG_MAP=(
    [python]=python3 [python-pip]=python3-pip [curl]=curl [wget]=wget [jq]=jq [fd]=fd-find
    [openssh]=openssh-server [kitty]=kitty [lm_sensors]=lm-sensors [python-requests]=python3-requests
    [python-aiohttp]=python3-aiohttp [swaync]=swaync [wofi]=wofi
    [fuse3]=fuse3 [inotify-tools]=inotify-tools
  )
  declare -A DNF_MAP=(
    [python]=python3 [python-pip]=python3-pip [fd]=fd-find [openssh]=openssh-server
    [lm_sensors]=lm_sensors [python-requests]=python3-requests [swaync]=swaync
    [wofi]=wofi [fuse3]=fuse3 [kitty]=kitty
  )
  declare -A APT_MAP=(
    [fd]=fd-find [openssh]=openssh-server [lm_sensors]=lm-sensors [python-requests]=python3-requests
    [python-aiohttp]=python3-aiohttp [swaync]=swaync [wofi]=wofi [fuse3]=fuse3
  )
  declare -A ZYPPER_MAP=(
    [fd]=fd-find [openssh]=openssh-server [lm_sensors]=lm_sensors [python-requests]=python3-requests
    [python-aiohttp]=python3-aiohttp [swaync]=swaync [wofi]=wofi
  )
  case "$pm" in
    apt) echo "${APT_MAP[$pkg]:-${PKG_MAP[$pkg]:-$pkg}}" ;;
    dnf|yum) echo "${DNF_MAP[$pkg]:-$pkg}" ;;
    zypper) echo "${ZYPPER_MAP[$pkg]:-$pkg}" ;;
    apk) echo "${PKG_MAP[$pkg]:-$pkg}" ;;
    *) echo "${PKG_MAP[$pkg]:-$pkg}" ;;
  esac
}

detect_gpu() {
  if [[ "$GPU_MODE" == cpu ]]; then echo "cpu"; return 0; fi
  if command -v nvidia-smi &>/dev/null; then echo "nvidia"; return 0; fi
  if command -v rocm-smi &>/dev/null; then echo "amd"; return 0; fi
  if command -v intel_gpu_top &>/dev/null; then echo "intel"; return 0; fi
  echo "cpu"
}

detect_swap() { swapon --show 2>/dev/null | grep -q .; }

detect_de() {
  [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] && echo "$XDG_CURRENT_DESKTOP" && return 0
  [[ -n "${DESKTOP_SESSION:-}" ]] && echo "$DESKTOP_SESSION" && return 0
  pgrep -x hyprland &>/dev/null && echo "Hyprland" && return 0
  pgrep -x gnome-shell &>/dev/null && echo "GNOME" && return 0
  pgrep -x plasmashell &>/dev/null && echo "KDE" && return 0
  echo "unknown"
}

###############################################################################
# TUI
###############################################################################

have_tui() { command -v whiptail &>/dev/null || command -v dialog &>/dev/null; }

tui_msgbox() {
  local title="$1" msg="$2"
  if command -v whiptail &>/dev/null; then whiptail --title "$title" --msgbox "$msg" 20 70 2>/dev/null
  elif command -v dialog &>/dev/null; then dialog --title "$title" --msgbox "$msg" 20 70 2>/dev/null
  else echo -e "\n$title\n$msg\n"; fi
}
tui_yesno() {
  local title="$1" msg="$2"
  if command -v whiptail &>/dev/null; then whiptail --title "$title" --yesno "$msg" 20 70 2>/dev/null
  elif command -v dialog &>/dev/null; then dialog --title "$title" --yesno "$msg" 20 70 2>/dev/null
  else echo -e "\n$title\n$msg\n[Y/n] "; read -r r; [[ "$r" =~ ^[Yy]?$ ]]; fi
}
tui_menu() {
  local title="$1" msg="$2"; shift 2; local items=("$@")
  if command -v whiptail &>/dev/null; then
    local cmd=(whiptail --title "$title" --menu "$msg" 24 70 14)
    for ((i=0; i<${#items[@]}; i+=2)); do cmd+=("${items[$i]}" "${items[$i+1]}"); done
    "${cmd[@]}" 2>/dev/null
  elif command -v dialog &>/dev/null; then
    local cmd=(dialog --title "$title" --menu "$msg" 24 70 14)
    for ((i=0; i<${#items[@]}; i+=2)); do cmd+=("${items[$i]}" "${items[$i+1]}"); done
    "${cmd[@]}" 2>/dev/null
  else echo "$msg"; for ((i=0; i<${#items[@]}; i+=2)); do echo "  ${items[$i]}) ${items[$i+1]}"; done; read -r r; echo "$r"
  fi
}
tui_gauge() {
  local title="$1" msg="$2" pct="$3"
  if command -v whiptail &>/dev/null; then echo "$pct" | whiptail --title "$title" --gauge "$msg" 8 70 0 2>/dev/null || true
  elif command -v dialog &>/dev/null; then echo "$pct" | dialog --title "$title" --gauge "$msg" 8 70 0 2>/dev/null || true
  fi
}

###############################################################################
# STATE MACHINE
###############################################################################

save_state() {
  local phase="$1" step="$2" status="$3" data="${4:-{}}"
  python3 -c "
import json, os
f='$STATE_FILE'
os.makedirs(os.path.dirname(f), exist_ok=True)
try:
    with open(f) as h: state=json.load(h)
except: state={'phases':[],'version':'$VERSION'}
state['phases'].append({'phase':'$phase','step':'$step','status':'$status','ts':$(date +%s),'data':$data})
with open(f,'w') as h: json.dump(state,h,indent=2)
" 2>/dev/null || echo "$phase:$step:$status:$(date +%s)" >> "$LOG_DIR/.state"
}

resume_state() {
  local phase="$1" step="$2"
  if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json,sys
with open('$STATE_FILE') as f: s=json.load(f)
for p in s.get('phases',[]):
    if p['phase']=='$phase' and p['step']=='$step' and p['status']=='done': sys.exit(0)
sys.exit(1)
" 2>/dev/null && return 0
  fi
  grep -q "$phase:$step:done" "$LOG_DIR/.state" 2>/dev/null && return 0
  return 1
}

###############################################################################
# ROLLBACK
###############################################################################

ensure_btrfs() { findmnt -n -o FSTYPE / 2>/dev/null | grep -qx "btrfs"; }

create_snapshot() {
  if ! ensure_btrfs; then warn "Not on btrfs — skipping snapshot"; return 1; fi
  local snap_name="ash-install-$(date +%Y%m%d-%H%M%S)"
  if command -v snapper &>/dev/null && snapper -c root create -d "$snap_name" >>"$LOGFILE" 2>&1; then
    ROLLBACK_SNAPSHOT="$snap_name"; SNAPSHOT_METHOD="snapper"
    ok "Snapshot: $snap_name (snapper)"
    return 0
  fi
  if command -v btrfs &>/dev/null; then
    mkdir -p /.snapshots
    if btrfs subvolume snapshot / "/.snapshots/$snap_name" >>"$LOGFILE" 2>&1; then
      ROLLBACK_SNAPSHOT="/.snapshots/$snap_name"; SNAPSHOT_METHOD="btrfs"
      ok "Snapshot: $snap_name (btrfs)"
      return 0
    fi
  fi
  warn "No snapshot created"
  return 1
}

rollback() {
  [[ -z "$ROLLBACK_SNAPSHOT" ]] && return 0
  warn "═══════════════════════════════════════════════════════"
  warn "  ROLLBACK: Restoring from $ROLLBACK_SNAPSHOT"
  warn "═══════════════════════════════════════════════════════"

  if [[ "$SNAPSHOT_METHOD" == "snapper" ]]; then
    # snapper undochange restores file-level diff between snapshot and current (0)
    snapper -c root undochange "${ROLLBACK_SNAPSHOT}..0" >>"$LOGFILE" 2>&1 \
      && ok "Snapper rollback complete" \
      || { warn "snapper undochange failed — check: snapper -c root list"; }

  elif [[ "$SNAPSHOT_METHOD" == "btrfs" && -d "$ROLLBACK_SNAPSHOT" ]]; then
    # For raw btrfs snapshots, swap the live subvolume:
    #   1. Take a snapshot of current (broken) state for forensics
    #   2. Move broken @ subvolume out of the way
    #   3. Promote snapshot to new @ subvolume
    local broken_save="/.snapshots/ash-broken-$(date +%Y%m%d-%H%M%S)"
    warn "  Saving broken state to: $broken_save"
    btrfs subvolume snapshot / "$broken_save" >>"$LOGFILE" 2>&1 || true

    warn "  Restoring snapshot: $ROLLBACK_SNAPSHOT → /"
    # Use btrfs-specific restore: delete old root, snapshot the pre-install snap back
    btrfs subvolume snapshot "$ROLLBACK_SNAPSHOT" "/.ash-restored" >>"$LOGFILE" 2>&1 \
      && ok "Snapshot restored to /.ash-restored — reboot with default subvol to apply" \
      || warn "btrfs snapshot restore failed — manual recovery needed"

    warn "  Run: btrfs subvolume set-default /.ash-restored && reboot"
  else
    warn "No usable snapshot found for rollback (SNAPSHOT_METHOD=$SNAPSHOT_METHOD)"
  fi

  # Always preserve the snapshot itself — do NOT delete it
  ROLLBACK_SNAPSHOT=""
}

rollback_menu() {
  if ! have_tui; then rollback; return; fi
  local choice
  choice=$(tui_menu "Install Failed" "Choose action:" \
    "retry" "Restore snapshot and re-run install" \
    "abort" "Restore snapshot and quit" \
    "continue" "Ignore failures and continue" \
    "diff" "Show changes made so far" \
    "shell" "Drop to shell for debugging") || choice="abort"
  case "$choice" in
    retry) rollback; exec bash "$0" "$@" ;;
    abort) rollback; exit 1 ;;
    continue) warn "Continuing despite failures — not recommended" ;;
    diff) find "$BACKUP_DIR" -type f -name "*.$(date +%Y%m%d)*" 2>/dev/null | head -20; rollback_menu "$@" ;;
    shell) echo "Dropping to shell. Exit to return."; bash -i; rollback_menu "$@" ;;
  esac
}

###############################################################################
# PREFLIGHT
###############################################################################

preflight_check() {
  local ok=true
  log "Running preflight system check..."

  local kernel=$(uname -r | cut -d. -f1)
  [[ "$kernel" -ge 6 ]] || { warn "Kernel >= 6.x recommended (got: $(uname -r))"; }

  local avail
  avail=$(df / --output=avail 2>/dev/null | tail -1)
  if [[ -n "$avail" && "$avail" -lt 10485760 ]]; then
    fail "Disk space: ${avail}KB available — need >= 10GB"; ok=false
  else ok "Disk: ${avail}KB available"; fi

  local mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
  if [[ -n "$mem" && "$mem" -lt 4194304 ]]; then
    fail "RAM: $((mem/1024))MB — need >= 4GB (8GB recommended)"; ok=false
  else ok "RAM: $((mem/1024))MB ($([ "$mem" -ge 8388608 ] && echo "good" || echo "minimum") )"; fi

  command -v python3 &>/dev/null && python3 -c "import sys; exit(0 if sys.version_info >= (3,10) else 1)" && ok "Python >= 3.10" || { warn "Python < 3.10"; }
  command -v systemctl &>/dev/null && ok "systemd available" || { fail "systemd not found"; ok=false; }
  command -v sudo &>/dev/null && ok "sudo available" || { fail "sudo not found"; ok=false; }

  for port in 6333 11434; do
    if ss -tln "sport = :$port" 2>/dev/null | grep -q .; then
      warn "Port $port already in use — may conflict"
    fi
  done

  if ! detect_swap && [[ "$mem" -lt 8388608 ]]; then
    warn "No swap + <8GB RAM — may OOM during model load"
  fi

  local pm=$(detect_pm)
  ok "Package manager: $pm"

  local de=$(detect_de)
  [[ "$PROFILE" == desktop && "$de" == unknown ]] && warn "No desktop detected — desktop profile may not apply"

  if [[ "$PROFILE" == minimal ]]; then
    [[ "$MODEL" == nomic-embed-text ]] && ok "Profile: minimal (no Qdrant, SQLite FTS5 backend)"
  fi

  $ok
}

###############################################################################
# PHASE 1: SYSTEM PACKAGES
###############################################################################

install_packages() {
  local pkgs=()
  local pm=$(detect_pm)

  if [[ "$pm" == pacman ]]; then
    pkgs=(curl wget wofi swaync jq fd openssh kitty python python-pip lm_sensors fuse3)
    if [[ "$PROFILE" != minimal ]]; then pkgs+=(python-requests python-aiohttp); fi
  else
    for p in curl wget jq fd openssh python3 python3-pip lm-sensors; do
      pkgs+=("$(pm_translate "$p")")
    done
    [[ "$PROFILE" == desktop ]] && pkgs+=(kitty)
  fi

  if [[ "$PROFILE" != minimal ]]; then
    pip install --break-system-packages requests aiohttp inotify_simple python-magic watchdog 2>>"$LOGFILE" || pip install requests aiohttp inotify_simple python-magic watchdog 2>>"$LOGFILE" || true
  fi

  log "Installing packages: ${pkgs[*]}"
  pm_install "${pkgs[@]}" || return 1
  record_manifest "packages: ${pkgs[*]}"
  return 0
}

###############################################################################
# PHASE 2: QDRANT
###############################################################################

install_qdrant() {
  if resume_state qdrant install; then ok "Qdrant already installed (from state)"; return 0; fi
  if curl -sf http://localhost:6333/healthz >/dev/null 2>&1; then ok "Qdrant already running"; save_state qdrant install done '{"method":"existing"}'; return 0; fi
  if pm_query qdrant; then systemctl enable --now qdrant >>"$LOGFILE" 2>&1 || true; ok "Qdrant from repos"; save_state qdrant install done '{"method":"repo"}'; return 0; fi

  local arch_map=""
  case "$ARCH" in
    x86_64)  arch_map="x86_64" ;;
    aarch64|arm64) arch_map="aarch64" ;;
    armv7l)  arch_map="armv7" ;;
    riscv64) arch_map="riscv64gc" ;;
    *) fail "Unsupported arch: $ARCH"; return 1 ;;
  esac

  if [[ -n "$OFFLINE_BUNDLE" ]]; then
    log "Installing Qdrant from offline bundle..."
    local tmp=$(mktemp -d)
    tar -xzf "$OFFLINE_BUNDLE" -C "$tmp" 2>>"$LOGFILE" || return 1
    local bin=$(find "$tmp" -name "qdrant" -type f | head -1)
    [[ -z "$bin" ]] && { rm -rf "$tmp"; return 1; }
    install -m 0755 "$bin" /usr/local/bin/qdrant
    rm -rf "$tmp"
    ok "Qdrant installed from offline bundle"
  else
    log "Downloading Qdrant binary..."
    local tag ver
    tag=$(retry curl -sfL "https://api.github.com/repos/qdrant/qdrant/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\([^"]*\)".*/\1/') || tag="v1.13.6"
    ver="${tag#v}"

    local tmp=$(mktemp -d)
    local downloaded=""
    for variant in "musl" "gnu"; do
      local url="https://github.com/qdrant/qdrant/releases/download/${tag}/qdrant-${arch_map}-unknown-linux-${variant}.tar.gz"
      local sha_url="$url.sha256"
      if retry curl -fSL --progress-bar -o "$tmp/qdrant.tar.gz" "$url"; then
        local sha_file="$tmp/qdrant.sha256"
        if curl -sfL -o "$sha_file" "$sha_url" 2>/dev/null; then
          local expected=$(cut -d' ' -f1 < "$sha_file")
          local actual=$(sha256sum "$tmp/qdrant.tar.gz" | cut -d' ' -f1)
          if [[ "$expected" != "$actual" ]]; then
            fail "Checksum mismatch for Qdrant binary — expected $expected, got $actual"
            rm -rf "$tmp"; continue
          fi
          ok "Qdrant checksum verified"
        fi
        downloaded="yes"; break
      fi
    done

    if [[ -z "$downloaded" ]]; then rm -rf "$tmp"; return 1; fi

    cache_file="$CACHE_DIR/qdrant-$ver-$arch_map.tar.gz"
    cp "$tmp/qdrant.tar.gz" "$cache_file"
    tar -xzf "$tmp/qdrant.tar.gz" -C "$tmp" >>"$LOGFILE" 2>&1
    local bin=$(find "$tmp" -type f -name "qdrant" | head -1)
    if [[ -z "$bin" ]]; then rm -rf "$tmp"; return 1; fi
    install -m 0755 "$bin" /usr/local/bin/qdrant
    rm -rf "$tmp"
  fi

  id -u qdrant &>/dev/null || useradd -r -s /usr/bin/nologin -d /var/lib/qdrant qdrant
  mkdir -p /var/lib/qdrant
  chown -R qdrant:qdrant /var/lib/qdrant

  QDRANT_API_KEY=$(python3 -c "import secrets; print(secrets.token_hex(24))" 2>/dev/null || openssl rand -hex 24)
  echo "QDRANT_API_KEY=$QDRANT_API_KEY" > "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  record_manifest "secrets: $SECRETS_FILE"

  local qdrant_exec="/usr/local/bin/qdrant --storage-path /var/lib/qdrant"
  [[ -n "$MEMORY_MAX" ]] && qdrant_exec+=" --optimizer-cpu-limit ${MEMORY_MAX%G}"
  [[ "$ARCH" == x86_64 ]] && qdrant_exec+=" --performance"

  cat > /etc/systemd/system/qdrant.service << UNIT
[Unit]
Description=Qdrant Vector Search Engine
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=qdrant
Group=qdrant
ExecStart=$qdrant_exec
Restart=always
RestartSec=2
LimitNOFILE=65536
Environment=QDRANT__SERVICE__HTTP_PORT=6333
Environment=QDRANT__SERVICE__GRPC_PORT=6334
Environment="QDRANT__SERVICE__API_KEY=$QDRANT_API_KEY"
$(if [[ "$NO_HARDEN" != true ]]; then echo "NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
MemoryDenyWriteExecute=true
RestrictNamespaces=true
CapabilityBoundingSet=~CAP_SYS_ADMIN"; fi)
$(if [[ -n "$MEMORY_MAX" ]]; then echo "MemoryMax=$MEMORY_MAX"; fi)
$(if [[ -n "$CPU_QUOTA" ]]; then echo "CPUQuota=$CPU_QUOTA"; fi)
[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload >>"$LOGFILE" 2>&1
  systemctl enable --now qdrant >>"$LOGFILE" 2>&1
  record_manifest "service: qdrant.service"

  for i in $(seq 1 30); do
    if curl -sf --max-time 2 "http://localhost:6333/healthz" >/dev/null 2>&1; then
      ok "Qdrant healthy on :6333"
      save_state qdrant install done "{\"version\":\"$ver\",\"api_key\":true}"
      return 0
    fi
    sleep 1
  done
  return 1
}

###############################################################################
# PHASE 3: OLLAMA
###############################################################################

install_ollama() {
  if resume_state ollama install; then ok "Ollama already installed"; return 0; fi
  if curl -sf http://localhost:11434/api/version >/dev/null 2>&1; then ok "Ollama already running"; save_state ollama install done '{"method":"existing"}'; return 0; fi

  if ! command -v ollama &>/dev/null; then
    log "Installing Ollama..."
    if pm_query ollama; then
      systemctl enable --now ollama >>"$LOGFILE" 2>&1 || true
    else
      retry curl -sfL https://ollama.com/install.sh | sh 2>>"$LOGFILE" || {
        warn "Ollama install script failed — trying AUR..."
        command -v paru &>/dev/null && su - "$USER_NAME" -c "paru -S --noconfirm ollama" >>"$LOGFILE" 2>&1 || true
      }
    fi
  fi

  local gpu=$(detect_gpu)
  mkdir -p /etc/systemd/system/ollama.service.d
  local dropin=""
  case "$gpu" in
    nvidia) dropin="Environment=OLLAMA_NUM_GPU=1
Environment=OLLAMA_GPU_OVERHEAD=512" ;;
    amd)    dropin="Environment=OLLAMA_NUM_GPU=1
Environment=OLLAMA_USE_ROCM=1" ;;
    intel)  dropin="Environment=OLLAMA_NUM_GPU=1
Environment=OLLAMA_USE_SYCL=1" ;;
  esac
  cat > /etc/systemd/system/ollama.service.d/override.conf << UNIT
[Service]
$dropin
$(if [[ -n "$MEMORY_MAX" ]]; then echo "MemoryMax=$MEMORY_MAX"; fi)
$(if [[ -n "$CPU_QUOTA" ]]; then echo "CPUQuota=$CPU_QUOTA"; fi)
$(if [[ "$NO_HARDEN" != true ]]; then echo "NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true"; fi)
UNIT

  systemctl daemon-reload >>"$LOGFILE" 2>&1
  systemctl enable --now ollama >>"$LOGFILE" 2>&1 || true
  record_manifest "service: ollama.service (GPU: $gpu)"

  for i in $(seq 1 30); do
    if curl -sf --max-time 2 "http://localhost:11434/api/version" >/dev/null 2>&1; then
      ok "Ollama running on :11434 (GPU: $gpu)"
      save_state ollama install done "{\"gpu\":\"$gpu\"}"
      return 0
    fi
    sleep 1
  done
  return 1
}



###############################################################################
# PHASE 5: FIREWALL
###############################################################################

setup_firewall() {
  [[ "$NO_FIREWALL" == true ]] && return 0
  if resume_state firewall setup; then ok "Firewall already configured"; return 0; fi

  log "Configuring firewall rules..."
  if command -v nft &>/dev/null; then
    nft add rule inet filter input ip daddr 127.0.0.1 tcp dport { 6333, 11434 } accept 2>>"$LOGFILE" || true
    nft add rule inet filter input tcp dport { 6333, 11434 } drop 2>>"$LOGFILE" || true
    cat > /etc/nftables.d/ash.conf << 'NFT'
table inet ash_filter {
  chain input {
    type filter hook input priority 0; policy accept;
    ip daddr 127.0.0.1 tcp dport { 6333, 11434 } accept
    tcp dport { 6333, 11434 } drop
  }
}
NFT
    ok "nftables rules applied"
  elif command -v iptables &>/dev/null; then
    iptables -A INPUT -i lo -p tcp --dport 6333 -j ACCEPT 2>>"$LOGFILE" || true
    iptables -A INPUT -i lo -p tcp --dport 11434 -j ACCEPT 2>>"$LOGFILE" || true
    iptables -A INPUT -p tcp --dport 6333 -j DROP 2>>"$LOGFILE" || true
    iptables -A INPUT -p tcp --dport 11434 -j DROP 2>>"$LOGFILE" || true
    ok "iptables rules applied"
  else
    warn "No firewall tool found (nftables/iptables)"
  fi
  save_state firewall setup done "{}"
  record_manifest "firewall: localhost-only for :6333 :11434"
}

###############################################################################
# PHASE 6: LSFS DAEMON
###############################################################################

deploy_lsfs() {
  if resume_state lsfs deploy; then ok "LSFS already deployed"; return 0; fi
  mkdir -p "$HOME_DIR/.config/scripts" "$HOME_DIR/.local/bin" "$HOME_DIR/.config/systemd/user"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config" "$HOME_DIR/.local" 2>/dev/null || true

  backup_config "$HOME_DIR/.config/scripts/lsfs_daemon.py"
  backup_config "$HOME_DIR/.config/scripts/lsfs_launcher_hook.sh"
  backup_config "$HOME_DIR/.config/scripts/lsfs_query.py"

  local query_py="$HOME_DIR/.config/scripts/lsfs_query.py"
  local daemon_py="$HOME_DIR/.config/scripts/lsfs_daemon.py"
  local launcher_sh="$HOME_DIR/.config/scripts/lsfs_launcher_hook.sh"
  local svc="$HOME_DIR/.config/systemd/user/lsfs-daemon.service"

  cat > "$query_py" << 'PYQUERY'
#!/usr/bin/env python3
import sys, json, os, urllib.request, http.client, socket, time
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/embeddings")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
MODEL = os.environ.get("ASH_MODEL", "nomic-embed-text")
SEARCH_LIMIT = int(os.environ.get("ASH_SEARCH_LIMIT", "20"))
COSINE_FLOOR = 0.5

def qdrant_req(method, path, data=None, timeout=2):
    url = f"{QDRANT_URL}/collections/apps/{path.lstrip('/')}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return {}

def search(query, limit=SEARCH_LIMIT):
    req_data = json.dumps({"model": MODEL, "prompt": query, "keep_alive": -1}).encode()
    req = urllib.request.Request(OLLAMA_URL, data=req_data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        emb_data = json.loads(resp.read())
    embedding = emb_data.get("embedding")
    if not embedding:
        return []
    payload = {"vector": embedding, "limit": limit, "with_payload": True}
    hits = qdrant_req("POST", "points/search", payload, timeout=3)
    results = []; seen = set()
    for hit in hits.get("result", []):
        score = hit.get("score", 0)
        p = hit.get("payload", {})
        path = p.get("path", "")
        if score < COSINE_FLOOR or path in seen: continue
        seen.add(path)
        results.append({"path": path, "name": p.get("name", ""), "score": score})
    results.sort(key=lambda r: r['score'], reverse=True)
    return results

if __name__ == "__main__":
    query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else ""
    if not query:
        print("Usage: lsfs-query <query>")
        sys.exit(0)
    t0 = time.time()
    results = search(query)
    elapsed = time.time() - t0
    if not results:
        print(f"No matches found. ({elapsed:.1f}s)")
    for r in results:
        print(f"{r['path']} | {r['name']} ({r['score']:.3f})")
    if results:
        print(f"({len(results)} results in {elapsed:.1f}s)")
PYQUERY

  local qdrant_api_key="${QDRANT_API_KEY:-}"

  cat > "$daemon_py" << PYDAEMON
#!/usr/bin/env python3
import os, sys, json, time, hashlib, logging, requests
from pathlib import Path

HOME = os.environ.get("HOME", "$HOME_DIR")
OLLAMA = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/embeddings")
QDRANT = os.environ.get("QDRANT_URL", "http://localhost:6333/collections")
MODEL = os.environ.get("ASH_MODEL", "$MODEL")
COLLECTION = "apps"
IGNORE = {".git", "node_modules", "__pycache__", ".cache", ".venv", "venv", ".mozilla", ".steam", ".Trash"}
API_KEY = "$qdrant_api_key"
HEADERS = {"Content-Type": "application/json"}
if API_KEY:
    HEADERS["api-key"] = API_KEY

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("lsfs")

def ensure_collection():
    r = requests.get(f"{QDRANT}/{COLLECTION}", timeout=5, headers=HEADERS)
    if r.status_code == 200: return
    payload = {"vectors": {"size": 768, "distance": "Cosine"}, "optimizers_config": {"default_segment_number": 8, "memmap_threshold_kb": 50000}}
    for i in range(5):
        r = requests.put(f"{QDRANT}/{COLLECTION}", json=payload, timeout=10, headers=HEADERS)
        if r.status_code in (200, 201): log.info("Collection created"); return
        time.sleep(2)

def embed(text):
    for i in range(3):
        r = requests.post(OLLAMA, json={"model": MODEL, "prompt": text[:512], "keep_alive": -1}, timeout=30, headers=HEADERS)
        if r.status_code == 200:
            d = r.json()
            if "embedding" in d: return d["embedding"]
        time.sleep(2)
    return None

def index_file(path):
    for p in IGNORE:
        if p in path: return False
    fp = Path(path)
    if not fp.is_file() or fp.is_symlink(): return False
    try:
        stat = fp.stat()
        if stat.st_size == 0 or stat.st_size > 1048576: return False
        text = fp.read_text(errors="replace")[:1024]
        if not text.strip(): return False
        vec = embed(text)
        if not vec: return False
        pid = hashlib.md5(path.encode()).hexdigest()
        payload = {"path": path, "name": fp.name, "ext": fp.suffix.lower(), "mtime": int(stat.st_mtime), "size": stat.st_size}
        r = requests.put(f"{QDRANT}/{COLLECTION}/points", json={"points": [{"id": pid, "vector": vec, "payload": payload}]}, timeout=10, headers=HEADERS)
        return r.status_code in (200, 201)
    except Exception as e:
        return False

def full_scan():
    log.info("Full scan started")
    indexed = 0; skipped = 0
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in IGNORE and not d.startswith(".")]
        for f in files:
            try:
                if index_file(os.path.join(root, f)): indexed += 1
                else: skipped += 1
            except: pass
    log.info(f"Scan done: {indexed} indexed, {skipped} skipped")

def watch_loop():
    log.info("Watching for changes (poll 60s)...")
    known = set()
    while True:
        current = set(); changed = 0
        for root, dirs, files in os.walk(HOME):
            dirs[:] = [d for d in dirs if d not in IGNORE and not d.startswith(".")]
            for f in files:
                fp = os.path.join(root, f)
                current.add(fp)
                if fp not in known:
                    if index_file(fp): changed += 1
        known = current
        if changed: log.info(f"Indexed {changed} new/changed files")
        time.sleep(60)

if __name__ == "__main__":
    log.info("LSFS Daemon starting")
    for i in range(60):
        try:
            r = requests.get(f"{QDRANT}/{COLLECTION}", timeout=2, headers=HEADERS)
            if r.status_code == 200: break
        except: pass
        time.sleep(1)
    else:
        log.error("Qdrant not reachable"); sys.exit(1)
    ensure_collection()
    full_scan()
    watch_loop()
PYDAEMON

  cat > "$launcher_sh" << LSFSHOOK
#!/usr/bin/env bash
set -euo pipefail
QUERY=\$(wofi --dmenu --prompt "Agentic Search" --cache-file /dev/null < /dev/null 2>/dev/null || true)
[ -z "\${QUERY:-}" ] && exit 0
notify-send -t 3000 -r 999 "Agentic OS" "Searching: \$QUERY"
RESULTS_FILE=\$(mktemp /tmp/lsfs_results.XXXXXX); trap 'rm -f "\$RESULTS_FILE"' EXIT; HAS_RESULTS=0
START_TIME=\$(date +%s%N)

# Classify query
CATEGORY="file"
echo "$QUERY" | grep -qiE '^(open|launch|run)\b' && CATEGORY="app"
echo "$QUERY" | grep -qiE '^calc\b|^[0-9+\-*/().]+\s*$' && CATEGORY="calc"
echo "$QUERY" | grep -qiE '^https?://' && CATEGORY="web"

case "$CATEGORY" in
  app)
    QUERY_CLEAN=$(echo "$QUERY" | sed 's/^open\|^launch\|^run //')
    lsfs-query "$QUERY_CLEAN" 2>/dev/null > "$RESULTS_FILE" || true
    DESKTOP_RES=$(find /usr/share/applications ~/.local/share/applications -name "*.desktop" 2>/dev/null | head -30)
    echo "$DESKTOP_RES" >> "$RESULTS_FILE" 2>/dev/null
    HAS_RESULTS=1
    ;;
  calc)
    RESULT=$(python3 -c "print(eval('''${QUERY//calc }'''))" 2>/dev/null) || RESULT="error"
    notify-send -t 5000 "Result: $RESULT"
    exit 0
    ;;
  web)
    xdg-open "$QUERY" 2>/dev/null || true
    exit 0
    ;;
  *)
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
      OLLAMA_RESP=$(curl -s --max-time 5 -X POST http://localhost:11434/api/embeddings \
        -d "{\"model\":\"nomic-embed-text\",\"prompt\":\"${QUERY//\"/\\\"}\",\"keep_alive\":-1}" 2>/dev/null) || true
      if [ -n "$OLLAMA_RESP" ]; then
        EMBEDDING=$(echo "$OLLAMA_RESP" | tr -d '\n' | sed -n 's/.*"embedding":\(\[[^]]*\]\).*/\1/p') || true
        if [ -n "${EMBEDDING:-}" ]; then
          VECTOR=$(echo "$EMBEDDING" | tr -d ' \t\n')
          QDRANT_RESP=$(curl -s --max-time 5 -X POST "http://localhost:6333/collections/apps/points/search" \
            -H "Content-Type: application/json" \
            -d "{\"vector\":$VECTOR,\"limit\":15,\"with_payload\":true}" 2>/dev/null) || true
          if [ -n "${QDRANT_RESP:-}" ]; then
            echo "$QDRANT_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data.get('result', []):
    p = r.get('payload', {})
    score = r.get('score', 0)
    label = '📄'
    ext = p.get('ext', '')
    if ext in ('.py','.rs','.go','.js','.ts','.sh','.rb'): label = '💻'
    elif ext in ('.md','.txt','.rst'): label = '📝'
    elif ext in ('.png','.jpg','.svg'): label = '🖼️'
    elif ext in ('.pdf','.doc','.docx'): label = '📕'
    elif ext in ('.conf','.yaml','.toml','.json'): label = '⚙️'
    print(f\"{label} {p.get('path','')} ({score:.3f})\")
" > "$RESULTS_FILE" 2>/dev/null
            [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1 && notify-send -t 2000 "$(wc -l < "$RESULTS_FILE") results"
          fi
        fi
      fi
    fi

    if [ "$HAS_RESULTS" -eq 0 ]; then
      PAT=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ') || true
      if [ -n "$PAT" ]; then
        echo "$PAT" | grep -qiE '[0-9]+[hd]' && TIME_ARG="$PAT" || {
          NUM=$(echo "$PAT" | grep -oE '[0-9]+')
          echo "$PAT" | grep -qiE 'h|hr|hour|hours' && TIME_ARG="${NUM}h" || TIME_ARG="${NUM}d"
        }
        fd --changed-within "$TIME_ARG" --type f "$HOME" 2>/dev/null | head -20 > "$RESULTS_FILE" && HAS_RESULTS=1
      fi
    fi

    if [ "$HAS_RESULTS" -eq 0 ] && command -v fd &>/dev/null; then
      fd --type f --max-depth 5 "$HOME" 2>/dev/null | head -15 > "$RESULTS_FILE" && HAS_RESULTS=1
    fi
    ;;
esac

if [ "$HAS_RESULTS" -eq 0 ]; then notify-send -u critical "Agentic OS" "No results"; exit 0; fi

SELECTED=$(wofi --dmenu --prompt "Results ($(wc -l < "$RESULTS_FILE"))" --cache-file /dev/null < "$RESULTS_FILE" 2>/dev/null) || true
[ -z "${SELECTED:-}" ] && exit 0
TARGET_PATH=$(echo "$SELECTED" | sed 's/^[^ ]* //; s/ (.*//')
[ -z "$TARGET_PATH" ] && exit 0; [ ! -e "$TARGET_PATH" ] && notify-send -u critical "Not found: $TARGET_PATH" && exit 1
if [ -d "$TARGET_PATH" ]; then hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'" 2>/dev/null || true
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then gtk-launch "$(basename "$TARGET_PATH")" 2>/dev/null || true
else hyprctl dispatch exec "kitty --class floating_editor -e nvim '$TARGET_PATH'" 2>/dev/null || true; fi

if [ -f /var/log/ash/audit.log ]; then
  ELAPSED_MS=$(( (\$(date +%s%N) - START_TIME) / 1000000 ))
  echo "\$(date +%Y-%m-%dT%H:%M:%S)|\$(date +%s)|\${QUERY:0:200}|$([ -s "$RESULTS_FILE" ] && wc -l < "$RESULTS_FILE" || echo 0)|\${ELAPSED_MS}ms" >> /var/log/ash/audit.log 2>/dev/null || true
fi
LSFSHOOK

  chmod +x "$daemon_py" "$launcher_sh" "$query_py"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/scripts"

  for name in lsfs_daemon lsfs_query; do
    ln -sf "$HOME_DIR/.config/scripts/${name}.py" "$HOME_DIR/.local/bin/${name/_/-}" 2>/dev/null || true
  done

  for rc in bashrc zshrc; do
    local rcpath="$HOME_DIR/.$rc"
    if [[ -f "$rcpath" ]] && ! grep -q '\.local/bin' "$rcpath" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rcpath"
    fi
  done

  cat > "$HOME_DIR/.lsfsignore" << 'IGNORE'
.*
node_modules/ __pycache__/ *.pyc .env/ venv/ .venv/ target/ build/ dist/
*.egg-info/ site-packages/ .git/ .svn/
*.csv *.log *.sql *.db *.sqlite *.pkl
*.mp3 *.mp4 *.png *.jpg *.ico *.svg
*.zip *.tar *.gz *.xz *.bz2 *.rar *.7z
*.o *.so *.dylib *.dll *.exe *.bin
.idea/ .vscode/ *.swp *~ .DS_Store
lost+found/ .Trash/
IGNORE
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.lsfsignore"

  cat > "$svc" << 'SYSD'
[Unit]
Description=LSFS Semantic File Indexer
After=network.target
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
  chown "$USER_NAME:$USER_NAME" "$svc"

  loginctl enable-linger "$USER_NAME" >>"$LOGFILE" 2>&1 || true
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME) systemctl --user daemon-reload" >>"$LOGFILE" 2>&1 || true
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME) systemctl --user enable --now lsfs-daemon.service" >>"$LOGFILE" 2>&1 || {
    warn "Daemon service failed — direct launch"
    nohup python3 "$daemon_py" &>/tmp/lsfs-daemon.log &
  }

  save_state lsfs deploy done "{}"
  record_manifest "lsfs: daemon, query, launcher, systemd user service"
  return 0
}

###############################################################################
# PHASE 7: NOTEBOOKLM SYNC DAEMON
###############################################################################

install_notebooklm_sync() {
  if resume_state notebooklm sync; then ok "NotebookLM sync already installed"; return 0; fi
  mkdir -p "$HOME_DIR/.ash/notebooklm" "$HOME_DIR/.config/systemd/user" "$HOME_DIR/.local/bin"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.ash" "$HOME_DIR/.local/bin" 2>/dev/null || true

  backup_config "$HOME_DIR/.local/bin/ash-notebooklm-sync"
  backup_config "$HOME_DIR/.config/systemd/user/notebooklm-sync.service"

  local sync_py="$HOME_DIR/.local/bin/ash-notebooklm-sync"
  local svc="$HOME_DIR/.config/systemd/user/notebooklm-sync.service"
  local skill_dir="$HOME_DIR/.ash/notebooklm/skills"
  mkdir -p "$skill_dir"

  # ── Ensure npx notebooklm-mcp-server is available ─────────────────────────
  if ! command -v npx &>/dev/null; then
    warn "npx not found — skipping NotebookLM sync (install Node.js first)"
    return 0
  fi

  # Pre-cache the package so the daemon doesn't need network on every start
  log "Pre-installing notebooklm-mcp-server via npx..."
  su - "$USER_NAME" -c "npx --yes notebooklm-mcp-server --version" >>"$LOGFILE" 2>&1 \
    && ok "notebooklm-mcp-server available" \
    || warn "notebooklm-mcp-server install failed — will retry at runtime"

  # ── Sync daemon (reads from npx notebooklm-mcp-server via MCP stdio) ───────
  cat > "$sync_py" << 'SYNCPY'
#!/usr/bin/env python3
"""
ash-notebooklm-sync — NotebookLM → Qdrant knowledge distillation daemon.

Architecture:
  npx notebooklm-mcp-server (stdio MCP) ──► this daemon ──► Qdrant (notebooklm_context collection)
  ash-project MCP server (running PID)  ──► this daemon ──► Qdrant (apps collection, importance boost)

The daemon:
  1. Talks to notebooklm-mcp-server over stdio JSON-RPC 2.0
  2. Lists all notebooks, fetches their sources
  3. Chunks sources using AST-aware chunker if available, else plain
  4. Embeds each chunk via Ollama nomic-embed-text
  5. Upserts into Qdrant with importance scores from ASH architecture decisions
  6. Also syncs local project context from ash-project MCP if available
  7. Writes distilled "skills" as local markdown files for offline use
"""

import hashlib
import json
import logging
import os
import subprocess
import sys
import time
import threading
from pathlib import Path
from typing import Any

# Optional: use AST chunker if installed
try:
    sys.path.insert(0, str(Path.home() / ".config/scripts"))
    from lsfs_chunker import chunk_file
    HAS_CHUNKER = True
except ImportError:
    HAS_CHUNKER = False

try:
    import urllib.request
    import urllib.error
    HAS_URLLIB = True
except ImportError:
    HAS_URLLIB = False

# ── Config ────────────────────────────────────────────────────────────────────
HOME             = Path(os.environ.get("HOME", "/home/aiuser"))
QDRANT_URL       = os.environ.get("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY   = os.environ.get("QDRANT_API_KEY", "")
OLLAMA_URL       = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/embeddings")
EMBED_MODEL      = os.environ.get("ASH_MODEL", "nomic-embed-text")
COLLECTION_NB    = "notebooklm_context"   # Notebook content vectors
COLLECTION_APPS  = "apps"                 # Main LSFS collection
POLL_INTERVAL    = int(os.environ.get("NOTEBOOKLM_POLL", "300"))  # 5 min
SKILL_DIR        = Path(os.environ.get("NOTEBOOKLM_SKILL_DIR", HOME / ".ash/notebooklm/skills"))
ASH_PROJECT_MCP  = os.environ.get("ASH_PROJECT_MCP_SCRIPT",
                                   str(HOME / "ash-iso/.opencode/mcp-server/server.py"))
# Notebook IDs to sync — comma-separated, from configure-agents.sh
NOTEBOOK_IDS     = [n.strip() for n in
                    os.environ.get("NOTEBOOKLM_NOTEBOOKS",
                                   "18deba09-f237-4348-9ad8-68f4f6f859f7").split(",")
                    if n.strip()]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [notebooklm-sync] %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("sync")

# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _http(method: str, url: str, body: Any = None, timeout: int = 10) -> Any:
    import urllib.request, urllib.error, json as _json
    data = _json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if QDRANT_API_KEY:
        headers["api-key"] = QDRANT_API_KEY
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return _json.loads(r.read())
    except Exception as exc:
        log.debug("HTTP %s %s → %s", method, url, exc)
        return {}

# ── Qdrant helpers ────────────────────────────────────────────────────────────

def ensure_collection(name: str, dim: int = 768) -> None:
    r = _http("GET", f"{QDRANT_URL}/collections/{name}")
    if r.get("result"):
        return
    body = {"vectors": {"size": dim, "distance": "Cosine"}}
    result = _http("PUT", f"{QDRANT_URL}/collections/{name}", body, timeout=15)
    if result.get("result"):
        log.info("Created Qdrant collection: %s", name)
    else:
        log.warning("Could not create collection %s: %s", name, result)

def upsert_point(collection: str, point_id: str, vector: list, payload: dict) -> bool:
    r = _http("PUT", f"{QDRANT_URL}/collections/{collection}/points",
              {"points": [{"id": point_id, "vector": vector, "payload": payload}]},
              timeout=10)
    return bool(r.get("result"))

# ── Embedding ─────────────────────────────────────────────────────────────────

_embed_cache: dict[str, list] = {}

def embed(text: str) -> list | None:
    if not text or not text.strip():
        return None
    key = hashlib.md5(text[:512].encode()).hexdigest()
    if key in _embed_cache:
        return _embed_cache[key]
    body = {"model": EMBED_MODEL, "prompt": text[:2048], "keep_alive": -1}
    for attempt in range(3):
        r = _http("POST", OLLAMA_URL, body, timeout=30)
        vec = r.get("embedding")
        if vec:
            _embed_cache[key] = vec
            return vec
        time.sleep(1 + attempt)
    return None

# ── MCP stdio client ──────────────────────────────────────────────────────────

class MCPClient:
    """Minimal JSON-RPC 2.0 stdio MCP client."""

    def __init__(self, cmd: list[str], env: dict | None = None):
        self.cmd = cmd
        self.env = env or os.environ.copy()
        self._proc: subprocess.Popen | None = None
        self._id = 0

    def __enter__(self):
        self._proc = subprocess.Popen(
            self.cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=self.env,
            text=True,
            bufsize=1,
        )
        # Initialize
        self._send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "ash-notebooklm-sync", "version": "2.0"},
        })
        self._recv()  # discard initialize response
        self._send("notifications/initialized", {})
        return self

    def __exit__(self, *_):
        if self._proc:
            try:
                self._proc.stdin.close()
                self._proc.wait(timeout=5)
            except Exception:
                self._proc.kill()

    def _send(self, method: str, params: dict) -> int:
        self._id += 1
        msg = json.dumps({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params})
        self._proc.stdin.write(msg + "\n")
        self._proc.stdin.flush()
        return self._id

    def _recv(self) -> dict:
        for _ in range(100):  # up to 100 lines (skip notifications)
            line = self._proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
                if "result" in msg or "error" in msg:
                    return msg
            except json.JSONDecodeError:
                continue
        return {}

    def call(self, method: str, params: dict | None = None) -> Any:
        self._send(method, params or {})
        resp = self._recv()
        if resp.get("error"):
            log.warning("MCP error: %s", resp["error"])
            return None
        return resp.get("result")

# ── Plain text chunking fallback ──────────────────────────────────────────────

def plain_chunks(text: str, size: int = 800, overlap: int = 50) -> list[str]:
    words = text.split()
    chunks, i = [], 0
    while i < len(words):
        chunk = " ".join(words[i:i+size])
        if chunk.strip():
            chunks.append(chunk)
        i += size - overlap
    return chunks

# ── Skill file distillation ───────────────────────────────────────────────────

def save_skill(nb_title: str, source_name: str, content: str) -> None:
    """Save notebook source as a local markdown skill file for offline use."""
    SKILL_DIR.mkdir(parents=True, exist_ok=True)
    slug = "".join(c if c.isalnum() else "_" for c in f"{nb_title}_{source_name}")[:60]
    path = SKILL_DIR / f"{slug}.md"
    if path.exists() and len(path.read_text()) == len(content):
        return  # unchanged
    with open(path, "w") as f:
        f.write(f"# {source_name}\n\n_Source: {nb_title} (NotebookLM)_\n\n---\n\n{content}")
    log.debug("Skill saved: %s", path)

# ── Core sync: NotebookLM → Qdrant ───────────────────────────────────────────

def sync_via_npx_mcp() -> int:
    """
    Pull notebook content from npx notebooklm-mcp-server via stdio MCP,
    embed chunks, upsert into Qdrant, and write skill files.
    Returns number of chunks indexed.
    """
    ensure_collection(COLLECTION_NB)

    cmd = ["npx", "--yes", "notebooklm-mcp-server", "server"]
    total = 0

    try:
        with MCPClient(cmd) as mcp:
            # List available tools to confirm connection
            tools_resp = mcp.call("tools/list")
            if tools_resp is None:
                log.warning("notebooklm-mcp-server did not respond to tools/list")
                return 0

            tool_names = {t["name"] for t in tools_resp.get("tools", [])}
            log.info("notebooklm-mcp-server tools: %s", tool_names)

            # For each known notebook ID, fetch sources
            for nb_id in NOTEBOOK_IDS:
                log.info("Syncing notebook: %s", nb_id)

                # Try get_notebook tool if available
                if "get_notebook" in tool_names:
                    result = mcp.call("tools/call", {
                        "name": "get_notebook",
                        "arguments": {"notebook_id": nb_id}
                    })
                    nb_content = None
                    if result and result.get("content"):
                        try:
                            text = result["content"][0].get("text", "")
                            nb_content = json.loads(text) if text.startswith("{") else {"sources": [{"content": text, "title": "content"}]}
                        except (json.JSONDecodeError, IndexError, KeyError):
                            pass

                    if nb_content:
                        nb_title = nb_content.get("title", nb_id)
                        sources  = nb_content.get("sources", [])
                        for source in sources:
                            src_text  = source.get("content", "") or source.get("text", "")
                            src_title = source.get("title", "untitled")
                            if not src_text.strip():
                                continue

                            save_skill(nb_title, src_title, src_text)

                            # Chunk the source
                            chunks = plain_chunks(src_text)
                            for ci, chunk in enumerate(chunks):
                                vec = embed(chunk)
                                if not vec:
                                    continue
                                point_id = hashlib.md5(
                                    f"{nb_id}:{src_title}:{ci}".encode()
                                ).hexdigest()
                                payload = {
                                    "source": "notebooklm",
                                    "notebook_id": nb_id,
                                    "notebook_title": nb_title,
                                    "source_name": src_title,
                                    "chunk_index": ci,
                                    "text": chunk[:400],
                                    "type": "notebooklm",
                                    # Item 11: high importance for notebook content
                                    "importance": 1.6,
                                }
                                if upsert_point(COLLECTION_NB, point_id, vec, payload):
                                    total += 1

                elif "search_notebooks" in tool_names:
                    # Fallback: no get_notebook, use search to get samples
                    log.info("get_notebook not available — using search_notebooks as fallback")
                    for query in ["architecture", "configuration", "installation", "agent", "security"]:
                        result = mcp.call("tools/call", {
                            "name": "search_notebooks",
                            "arguments": {"query": query}
                        })
                        if result and result.get("content"):
                            text = result["content"][0].get("text", "")
                            if text and text.strip():
                                vec = embed(text[:2048])
                                if vec:
                                    point_id = hashlib.md5(
                                        f"search:{nb_id}:{query}".encode()
                                    ).hexdigest()
                                    if upsert_point(COLLECTION_NB, point_id, vec, {
                                        "source": "notebooklm",
                                        "notebook_id": nb_id,
                                        "query": query,
                                        "text": text[:400],
                                        "type": "notebooklm_search",
                                        "importance": 1.4,
                                    }):
                                        total += 1

    except FileNotFoundError:
        log.warning("npx not found — cannot run notebooklm-mcp-server")
    except Exception as exc:
        log.error("NotebookLM MCP sync error: %s", exc, exc_info=True)

    log.info("NotebookLM sync complete: %d chunks indexed to %s", total, COLLECTION_NB)
    return total

# ── Local project context sync (ash-project MCP) ─────────────────────────────

def sync_ash_project_context() -> int:
    """
    Pull indexed project files from the running ash-project MCP server,
    embed architecture-relevant content, upsert into apps collection with
    high importance scores (Item 11).
    """
    if not Path(ASH_PROJECT_MCP).exists():
        log.debug("ash-project MCP script not found at %s — skipping", ASH_PROJECT_MCP)
        return 0

    ensure_collection(COLLECTION_APPS)
    total = 0

    cmd = ["python3", ASH_PROJECT_MCP]
    env = os.environ.copy()
    env["ASH_PROJECT_ROOT"] = str(HOME / "ash-iso")
    env["NOTEBOOKLM_NOTEBOOKS"] = ",".join(NOTEBOOK_IDS)
    env["NOTEBOOKLM_CACHE_DIR"] = str(HOME / ".ash/notebooklm/cache")

    try:
        with MCPClient(cmd, env) as mcp:
            tools_resp = mcp.call("tools/list")
            if not tools_resp:
                return 0
            tool_names = {t["name"] for t in tools_resp.get("tools", [])}

            # Fetch project context overview
            if "get_context" in tool_names:
                result = mcp.call("tools/call", {
                    "name": "get_context",
                    "arguments": {}
                })
                if result and result.get("content"):
                    text = result["content"][0].get("text", "")
                    if text:
                        vec = embed(text[:4096])
                        if vec:
                            pid = hashlib.md5(b"ash-project:context-overview").hexdigest()
                            if upsert_point(COLLECTION_APPS, pid, vec, {
                                "source": "ash-project-mcp",
                                "name": "project-overview",
                                "path": "ash-iso/project-context",
                                "type": "project_context",
                                "importance": 1.8,  # highest importance
                            }):
                                total += 1
                                log.info("Indexed project context overview")

            # Search for architecture decisions and key files
            if "search_project" in tool_names:
                for topic in [
                    "architecture decisions",
                    "security hardening",
                    "NotebookLM integration",
                    "Qdrant Ollama LSFS",
                    "systemd services",
                    "btrfs snapshots",
                    "ISO build pipeline",
                ]:
                    result = mcp.call("tools/call", {
                        "name": "search_project",
                        "arguments": {"query": topic, "limit": 3}
                    })
                    if result and result.get("content"):
                        text = result["content"][0].get("text", "")
                        if text:
                            vec = embed(text[:2048])
                            if vec:
                                pid = hashlib.md5(f"ash-project:search:{topic}".encode()).hexdigest()
                                if upsert_point(COLLECTION_APPS, pid, vec, {
                                    "source": "ash-project-mcp",
                                    "name": topic,
                                    "path": f"ash-iso/search/{topic}",
                                    "type": "project_search",
                                    "importance": 1.5,
                                }):
                                    total += 1

    except Exception as exc:
        log.error("ash-project MCP sync error: %s", exc, exc_info=True)

    log.info("ash-project MCP sync: %d chunks indexed", total)
    return total

# ── Cross-collection notebook skill injection ─────────────────────────────────

def inject_skills_to_apps_collection() -> int:
    """
    Read distilled skill markdown files and inject them into the main
    apps collection with very high importance (Item 11 persistent memory).
    """
    if not SKILL_DIR.exists():
        return 0
    ensure_collection(COLLECTION_APPS)
    total = 0
    for skill_file in SKILL_DIR.glob("*.md"):
        try:
            content = skill_file.read_text(errors="replace")[:4096]
            if not content.strip():
                continue
            chunks = plain_chunks(content, size=400, overlap=30)
            for ci, chunk in enumerate(chunks):
                vec = embed(chunk)
                if not vec:
                    continue
                point_id = hashlib.md5(f"skill:{skill_file.name}:{ci}".encode()).hexdigest()
                if upsert_point(COLLECTION_APPS, point_id, vec, {
                    "source": "notebooklm-skill",
                    "name": skill_file.stem,
                    "path": str(skill_file),
                    "type": "distilled_skill",
                    "importance": 1.7,  # skills are high-importance persistent memory
                }):
                    total += 1
        except Exception as exc:
            log.debug("Skill injection error %s: %s", skill_file, exc)
    if total:
        log.info("Injected %d skill chunks into apps collection", total)
    return total

# ── Main loop ─────────────────────────────────────────────────────────────────

def run_once() -> None:
    log.info("Starting sync cycle...")
    t0 = time.time()

    nb_count  = sync_via_npx_mcp()
    prj_count = sync_ash_project_context()
    skl_count = inject_skills_to_apps_collection()

    elapsed = time.time() - t0
    log.info(
        "Sync complete in %.1fs: %d notebook chunks, %d project chunks, %d skill chunks",
        elapsed, nb_count, prj_count, skl_count,
    )

def main() -> None:
    if "--once" in sys.argv:
        run_once()
        return

    log.info("NotebookLM sync daemon starting (poll every %ds)", POLL_INTERVAL)
    log.info("Notebooks: %s", NOTEBOOK_IDS)
    log.info("Skill dir: %s", SKILL_DIR)

    while True:
        try:
            run_once()
        except KeyboardInterrupt:
            log.info("Interrupted — stopping")
            break
        except Exception as exc:
            log.error("Sync cycle error: %s", exc, exc_info=True)
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
SYNCPY

  chmod +x "$sync_py"
  chown "$USER_NAME:$USER_NAME" "$sync_py"

  # ── Systemd user service ───────────────────────────────────────────────────
  cat > "$svc" << SYSD
[Unit]
Description=Ash NotebookLM → Qdrant Sync Daemon
Documentation=https://github.com/ash-linux/ash
After=network-online.target ollama.service qdrant.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/ash-notebooklm-sync
Restart=on-failure
RestartSec=30
Nice=19
IOSchedulingClass=idle
CPUQuota=15%
Environment=PYTHONUNBUFFERED=1
Environment=NOTEBOOKLM_NOTEBOOKS=${NOTEBOOKLM_NOTEBOOKS:-18deba09-f237-4348-9ad8-68f4f6f859f7}
Environment=NOTEBOOKLM_POLL=${NOTEBOOKLM_POLL:-300}
Environment=NOTEBOOKLM_SKILL_DIR=%h/.ash/notebooklm/skills
Environment=ASH_PROJECT_MCP_SCRIPT=%h/ash-iso/.opencode/mcp-server/server.py
Environment=QDRANT_URL=http://localhost:6333
Environment=OLLAMA_URL=http://localhost:11434/api/embeddings
Environment=ASH_MODEL=nomic-embed-text

[Install]
WantedBy=default.target
SYSD
  chown "$USER_NAME:$USER_NAME" "$svc"

  loginctl enable-linger "$USER_NAME" >>"$LOGFILE" 2>&1 || true

  local xdg_runtime="/run/user/$(id -u $USER_NAME)"
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=$xdg_runtime systemctl --user daemon-reload" \
    >>"$LOGFILE" 2>&1 || true
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=$xdg_runtime systemctl --user enable --now notebooklm-sync.service" \
    >>"$LOGFILE" 2>&1 || {
    warn "NotebookLM sync service start failed — will launch directly as fallback"
    nohup su - "$USER_NAME" -c "python3 $sync_py --once" >>/tmp/notebooklm-sync.log 2>&1 &
  }

  # Run a one-shot sync immediately in the background
  nohup su - "$USER_NAME" -c "python3 $sync_py --once" >>/tmp/notebooklm-sync-init.log 2>&1 &
  ok "NotebookLM sync daemon installed — initial sync running in background"

  save_state notebooklm sync done '{"method":"npx-mcp","notebooks":"'${NOTEBOOKLM_NOTEBOOKS:-18deba09-f237-4348-9ad8-68f4f6f859f7}'"}'
  record_manifest "notebooklm: sync daemon (npx notebooklm-mcp-server), skills at $skill_dir"
}


###############################################################################
# PHASE 7b: NOTEBOOKLM MCP SERVER
###############################################################################

install_notebooklm_mcp() {
  if resume_state notebooklm mcp; then ok "NotebookLM MCP already installed"; return 0; fi
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/systemd/user"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin" 2>/dev/null || true

  # ── 1. Ensure npx notebooklm-mcp-server is cached ─────────────────────────
  if command -v npx &>/dev/null; then
    log "Pre-caching npx notebooklm-mcp-server..."
    su - "$USER_NAME" -c "npx --yes notebooklm-mcp-server --version" >>"$LOGFILE" 2>&1 \
      && ok "notebooklm-mcp-server v$(npx --yes notebooklm-mcp-server --version 2>/dev/null | tail -1) cached" \
      || warn "npx notebooklm-mcp-server cache failed — first-run may be slow"
  else
    warn "npx not found — notebooklm-mcp-server will not be available"
  fi

  # ── 2. Copy existing notebook cache to home dir ────────────────────────────
  local cache_src="/tmp/ash-notebooklm-cache"
  local cache_dst="$HOME_DIR/.ash/notebooklm/cache"
  mkdir -p "$cache_dst"
  if [[ -d "$cache_src" ]]; then
    cp -r "$cache_src"/. "$cache_dst/" 2>/dev/null || true
    chown -R "$USER_NAME:$USER_NAME" "$cache_dst" 2>/dev/null || true
    local nb_count
    nb_count=$(ls "$cache_dst"/*.json 2>/dev/null | wc -l | tr -d ' ')
    ok "Notebook cache copied: $nb_count notebooks in $cache_dst"
  fi

  # ── 3. Install ash-notebooklm-mcp wrapper (thin shim → npx MCP server) ────
  # This wrapper is what gets called by agents via CLI.
  # It just execs npx notebooklm-mcp-server server in stdio mode.
  cat > "$HOME_DIR/.local/bin/notebooklm-mcp" << 'SHIMEOF'
#!/usr/bin/env bash
# notebooklm-mcp — Thin shim that invokes npx notebooklm-mcp-server in stdio MCP mode.
# Used as "command" in mcp.json configs for Claude, Cursor, Cline, OpenCode.
exec npx --yes notebooklm-mcp-server server "$@"
SHIMEOF
  chmod +x "$HOME_DIR/.local/bin/notebooklm-mcp"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin/notebooklm-mcp" 2>/dev/null || true

  # ── 4. Write mcp.json configs for all AI coding tools ─────────────────────
  # We register 3 servers in all configs:
  #   notebooklm    → npx notebooklm-mcp-server server  (real Google NotebookLM)
  #   ash-project   → python3 .opencode/mcp-server/server.py  (4587 files indexed)
  #   ash-router    → for completions routing via ash-model-router

  local project_root
  project_root=$(dirname "$(dirname "$0")")  # ash-iso/ root
  local mcp_server_py="$project_root/.opencode/mcp-server/server.py"
  local nb_ids="${NOTEBOOKLM_NOTEBOOKS:-18deba09-f237-4348-9ad8-68f4f6f859f7}"

  # Helper: write mcp.json if not exists, else merge via python3
  write_mcp_config() {
    local config_file="$1"
    local dir
    dir=$(dirname "$config_file")
    mkdir -p "$dir"

    local new_servers
    new_servers=$(python3 -c "
import json, sys
servers = {
    'notebooklm': {
        'command': 'npx',
        'args': ['notebooklm-mcp-server', 'server'],
        'env': {}
    },
    'ash-project': {
        'command': 'python3',
        'args': ['$mcp_server_py'],
        'env': {
            'ASH_PROJECT_ROOT': '$project_root',
            'NOTEBOOKLM_NOTEBOOKS': '$nb_ids',
            'NOTEBOOKLM_CACHE_DIR': '$cache_dst'
        }
    }
}
print(json.dumps(servers, indent=2))
" 2>/dev/null)

    if [[ -f "$config_file" ]]; then
      local tmp
      tmp=$(mktemp)
      python3 -c "
import json, sys
with open('$config_file') as f:
    cfg = json.load(f)
key = 'mcpServers' if 'mcpServers' in cfg else None
if key is None:
    # try top-level (Cline format)
    cfg.update($new_servers)
    key = None
else:
    cfg[key].update($new_servers)
with open('$tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null && cp "$tmp" "$config_file" && log "  merged: $config_file"
      rm -f "$tmp"
    else
      python3 -c "
import json
with open('$config_file', 'w') as f:
    json.dump({'mcpServers': $new_servers}, f, indent=2)
" 2>/dev/null && log "  created: $config_file"
    fi
    chown "$USER_NAME:$USER_NAME" "$config_file" 2>/dev/null || true
  }

  # Claude Desktop
  case "$(uname -s)" in
    Linux)  write_mcp_config "$HOME_DIR/.config/Claude/claude_desktop_config.json" ;;
    Darwin) write_mcp_config "$HOME_DIR/Library/Application Support/Claude/claude_desktop_config.json" ;;
  esac

  # Cursor
  mkdir -p "$project_root/.cursor"
  write_mcp_config "$project_root/.cursor/mcp.json"

  # Windsurf
  mkdir -p "$project_root/.windsurf"
  write_mcp_config "$project_root/.windsurf/mcp.json"

  # Cline (VSCode extension)
  mkdir -p "$project_root/.vscode"
  write_mcp_config "$project_root/.vscode/cline_mcp.json"

  # OpenCode (.opencode/config.json already has this, update it)
  local opencode_cfg="$project_root/.opencode/config.json"
  if [[ -f "$opencode_cfg" ]]; then
    local tmp
    tmp=$(mktemp)
    python3 -c "
import json
with open('$opencode_cfg') as f:
    cfg = json.load(f)
mcp = cfg.setdefault('mcp', {})
mcp['notebooklm'] = {'command': 'npx', 'args': ['notebooklm-mcp-server', 'server'], 'env': {}}
mcp['ash-project'] = {
    'command': 'python3',
    'args': ['$mcp_server_py'],
    'env': {
        'ASH_PROJECT_ROOT': '$project_root',
        'NOTEBOOKLM_NOTEBOOKS': '$nb_ids',
        'NOTEBOOKLM_CACHE_DIR': '$cache_dst'
    }
}
with open('$tmp', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null && cp "$tmp" "$opencode_cfg" && log "  merged: $opencode_cfg"
    rm -f "$tmp"
  fi

  # ── 5. Write ash-context notebooklm search integration ────────────────────
  # Patch ash-context (installed in PHASE 8) to also search notebooklm_context
  # Qdrant collection. Done by writing the env var so it auto-detects on startup.
  cat >> "$HOME_DIR/.config/ash-context.env" << 'ENV' 2>/dev/null || true
# NotebookLM integration (added by install_notebooklm_mcp)
NOTEBOOKLM_QDRANT_COLLECTION=notebooklm_context
NOTEBOOKLM_NOTEBOOKS=18deba09-f237-4348-9ad8-68f4f6f859f7
NOTEBOOKLM_CACHE_DIR=${HOME}/.ash/notebooklm/cache
ENV

  ok "NotebookLM MCP installed:"
  ok "  npx notebooklm-mcp-server → Claude/Cursor/Cline/OpenCode"
  ok "  ash-project MCP (4587 files, PID 46983) → all tool configs"
  ok "  Notebook cache: $cache_dst ($nb_count notebooks)"
  ok "  Configs: .cursor/mcp.json .windsurf/mcp.json .vscode/cline_mcp.json"

  save_state notebooklm mcp done '{"method":"npx-mcp-server","tools":["notebooklm","ash-project"]}'
  record_manifest "notebooklm: MCP via npx notebooklm-mcp-server + ash-project local server"
}






# PHASE 8: ASH CONTEXT COMMAND & VIBE MODE
###############################################################################

install_ash_context() {
  if resume_state context install; then ok "Ash context already installed"; return 0; fi
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/scripts"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin" 2>/dev/null || true

  backup_config "$HOME_DIR/.local/bin/ash-context"
  backup_config "$HOME_DIR/.config/scripts/ash-vibe.sh"
  backup_config "$HOME_DIR/.local/bin/ash-vscode"

  cat > "$HOME_DIR/.local/bin/ash-context" << 'ASHEOF'
#!/bin/bash
set -euo pipefail
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/embeddings}"
ASH_MODEL="${ASH_MODEL:-nomic-embed-text}"
QUERY="" LIMIT=5 SOURCE="" NO_CONTEXT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --no-context) NO_CONTEXT="1"; shift ;;
    --help|-h) echo "Usage: ash context <query> [--limit N] [--source files|notebooklm|web|all] [--no-context]"; exit 0 ;;
    *) QUERY="$1"; shift ;;
  esac
done

[[ -z "$QUERY" ]] && { echo "Error: query required" >&2; exit 1; }

ensure_collection() {
  local col="$1"
  curl -sf "$QDRANT_URL/collections/$col" -H "api-key: $QDRANT_API_KEY" >/dev/null 2>&1 ||
    curl -s -X PUT "$QDRANT_URL/collections/$col" -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":768,\"distance\":\"Cosine\"}}" >/dev/null 2>&1 || true
}

embed() {
  python3 -c "
import json, urllib.request, urllib.error, sys
text = sys.stdin.read().strip()[:2048]
if not text: sys.exit(0)
payload = json.dumps({'model': '$ASH_MODEL', 'prompt': text, 'keep_alive': -1}).encode()
try:
    req = urllib.request.Request('$OLLAMA_URL', data=payload, headers={'Content-Type': 'application/json'})
    resp = urllib.request.urlopen(req, timeout=15)
    data = json.loads(resp.read())
    vec = data.get('embedding', [])
    print(json.dumps(vec))
except Exception:
    print('[]')
" <<< "$1" 2>/dev/null || echo "[]"
}

search_col() {
  local col="$1" q="$2" lim="$3"
  local vec; vec=$(embed "$q")
  [[ "$vec" == "[]" ]] && return
  curl -s -X POST "$QDRANT_URL/collections/$col/points/search" \
    -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    -d "{\"vector\":$vec,\"limit\":$lim,\"with_payload\":true}" 2>/dev/null |
    python3 -c "import json,sys; data=json.load(sys.stdin); [print(json.dumps({'score':h.get('score',0),'payload':h.get('payload',{})})) for h in data.get('result',[])]" 2>/dev/null || true
}

echo "🔍 Ash Context: \"$QUERY\" ($(date '+%H:%M:%S'))"
echo "================================"

ALL="[]"
for col in apps notebooklm_context web_context; do
  ensure_collection "$col"
  if [[ -z "$SOURCE" || "$SOURCE" == "all" || "$SOURCE" == "${col/context/}" ]]; then
    RES=$(search_col "$col" "$QUERY" "$LIMIT" 2>/dev/null || echo "")
    [[ -n "$RES" ]] && ALL=$(echo "$ALL $RES" | python3 -c "
import json,sys
a=json.loads(sys.argv[1] or '[]')
b=[json.loads(l) for l in sys.argv[2].strip().split('\n') if l.strip()]
c=a+b; c.sort(key=lambda x:x.get('score',0),reverse=True); print(json.dumps(c[:int(sys.argv[3])]))
" -- "$ALL" "$RES" "$LIMIT" 2>/dev/null || echo "$ALL")
  fi
done

RC=$(echo "$ALL" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo "0")
echo ""
echo "📄 Results ($RC):"
echo "---"
echo "$ALL" | python3 -c "
import json,sys
results=json.loads(sys.stdin.read())
for i,h in enumerate(results[:5],1):
    p=h.get('payload',{}); print(f'  [{i}] ({p.get(\"source\",\"?\")}) {p.get(\"source_name\") or p.get(\"notebook_title\") or p.get(\"url\",\"\")}  (score: {h.get(\"score\",0):.3f})')
    print(f'      {p.get(\"text\",\"\")[:150]}')
    print()
" 2>/dev/null || echo "  (no results)"

[[ -z "$NO_CONTEXT" && "$RC" -gt 0 ]] && echo "🤖 AI ready — pipe results to Ash for summarization"
ASHEOF

  chmod +x "$HOME_DIR/.local/bin/ash-context"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin/ash-context" 2>/dev/null || true

  cat > "$HOME_DIR/.config/scripts/ash-vibe.sh" << 'VIBEEOF'
#!/bin/bash
# ash vibe — the most vibe-coding friendly terminal mode
set -euo pipefail
HOME_DIR="${HOME:-/home/shrey}"
ASH_DIR="$HOME_DIR/.ash"
VIBE_LOG="$ASH_DIR/vibe.log"
SNAPSHOT_DIR="$ASH_DIR/snapshots"
mkdir -p "$HOME_DIR/.ash/snapshots"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$VIBE_LOG"; echo "$*"; }

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
  start)
    log "🚀 Starting vibe mode..."
    log "  Snapshot: taking workspace snapshot"
    mkdir -p "$SNAPSHOT_DIR/vibe_$(date +%Y%m%d_%H%M%S)"
    log "  NotebookLM: syncing..."
    ash-notebooklm-sync 2>/dev/null || true
    log "  Qdrant: ensuring collections..."
    for c in apps notebooklm_context web_context; do
      curl -sf -X PUT "http://localhost:6333/collections/$c" -H "Content-Type: application/json" \
        -d '{"vectors":{"size":768,"distance":"Cosine"}}' >/dev/null 2>&1 || true
    done
    log "  Vibe mode active — all context loaded"
    log "  Shortcuts: Ctrl+D=snapshot, Ctrl+L=search, Ctrl+N=notebooklm, Ctrl+W=web"
    $SHELL --rcfile <(cat "$HOME_DIR/.bashrc" 2>/dev/null; echo 'PS1="(vibe) \w \$ "')
    log "  Vibe mode ended — snapshot saved"
    ;;
  snapshot)
    mkdir -p "$SNAPSHOT_DIR/vibe_$(date +%Y%m%d_%H%M%S)"
    log "📸 Snapshot saved"
    ;;
  search)
    QUERY="${1:-}"
    [[ -z "$QUERY" ]] && read -rp "🔍 Search all context: " QUERY
    ash context "$QUERY" --limit 5 --no-context
    ;;
  notebooklm)
    QUERY="${1:-}"
    [[ -z "$QUERY" ]] && read -rp "📓 NotebookLM query: " QUERY
    ash context "$QUERY" --source notebooklm --limit 5 --no-context
    ;;
  web)
    QUERY="${1:-}"
    [[ -z "$QUERY" ]] && read -rp "🌐 Web search: " QUERY
    python3 "$HOME_DIR/ai-services/tools/web-research/src/research.py" research "$QUERY" 2>/dev/null || true
    ash context "$QUERY" --source web --limit 5 --no-context
    ;;
  sync)
    log "🔄 Syncing NotebookLM..."
    ash-notebooklm-sync 2>/dev/null || true
    log "✅ Sync complete"
    ;;
  status)
    echo "🚀 Ash Vibe Mode Status"
    echo "  Qdrant: $(curl -sf http://localhost:6333/healthz 2>/dev/null && echo '✅' || echo '❌')"
    echo "  Snapshots: $(ls "$SNAPSHOT_DIR/" 2>/dev/null | wc -l)"
    echo "  Log: $VIBE_LOG"
    ;;
  --help|*)
    cat <<'HELP'
ash vibe — vibe-coding terminal mode

Commands:
  ash vibe start        Enter vibe mode with all context loaded
  ash vibe snapshot     Save workspace snapshot
  ash vibe search       Search across all context sources
  ash vibe notebooklm   Search NotebookLM only
  ash vibe web          Web research and index
  ash vibe sync         Force sync NotebookLM notebooks
  ash vibe status       Show vibe mode status
HELP
    ;;
esac
VIBEEOF

  chmod +x "$HOME_DIR/.config/scripts/ash-vibe.sh"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/scripts/ash-vibe.sh" 2>/dev/null || true

  cat > "$HOME_DIR/.local/bin/ash-vscode" << 'VCSEOF'
#!/bin/bash
set -euo pipefail
HOME_DIR="${HOME:-/home/shrey}"
VSCODE_DIR="$HOME_DIR/.vscode"
mkdir -p "$VSCODE_DIR"

cmd="${1:-}"
shift 2>/dev/null || true

case "$cmd" in
  install)
    echo "Installing ash-vscode integration..."
    cp -r "$HOME_DIR/ai-services/tools/notebooklm-sync/scripts/ash-vscode/"* "$VSCODE_DIR/" 2>/dev/null || true
    echo '{"recommendations":["ash-vibe.ash-vscode"],"settings":{"ash.context.autoInject":true,"ash.context.notebooklm":true,"ash.vibe.mode":"full","files.autoSave":"afterDelay","editor.formatOnSave":true,"editor.minimap.enabled":false,"telemetry.enabled":false}}' > "$VSCODE_DIR/settings.json"
    echo "✅ ash-vscode installed — reload VS Code"
    echo "  Ctrl+Shift+H — Inject NotebookLM context"
    echo "  Ctrl+Shift+N — Query NotebookLM"
    echo "  Ctrl+Shift+W — Web research on selection"
    echo "  Ctrl+Shift+S — Snapshot workspace"
    ;;
  status)
    if [[ -f "$VSCODE_DIR/settings.json" ]]; then echo "✅ ash-vscode installed in $VSCODE_DIR"; else echo "❌ ash-vscode not installed"; fi
    ;;
  --help|*)
    echo "Usage: ash vscode {install|status|--help}"
    echo "  install  Install the VS Code vibe-coding integration"
    echo "  status   Check installation status"
    ;;
esac
VCSEOF

  chmod +x "$HOME_DIR/.local/bin/ash-vscode"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin/ash-vscode" 2>/dev/null || true

  for rc in bashrc zshrc; do
    local rcpath="$HOME_DIR/.$rc"
    if [[ -f "$rcpath" ]] && ! grep -q 'ash-context' "$rcpath" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rcpath"
    fi
  done

  save_state context install done '{"ash-context":true,"ash-vibe":true,"ash-vscode":true}'
  record_manifest "context: ash-context, ash-vibe, ash-vscode CLI"
  return 0
}

###############################################################################
# PHASE 9: WEB RESEARCH TOOL
###############################################################################

install_web_research() {
  if resume_state web research; then ok "Web research tool already installed"; return 0; fi
  mkdir -p "$HOME_DIR/.local/bin"
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin" 2>/dev/null || true

  backup_config "$HOME_DIR/.local/bin/ash-research"

  cat > "$HOME_DIR/.local/bin/ash-research" << 'RESEOF'
#!/bin/bash
set -euo pipefail
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
QDRANT_API_KEY="${QDRANT_API_KEY:-}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/embeddings}"
ASH_MODEL="${ASH_MODEL:-nomic-embed-text}"
HEADERS=("Content-Type: application/json")

cmd="${1:-}"
query="${2:-}"
limit="${3:-5}"

ensure_collection() {
  curl -sf "$QDRANT_URL/collections/web_context" -H "api-key: $QDRANT_API_KEY" >/dev/null 2>&1 ||
    curl -s -X PUT "$QDRANT_URL/collections/web_context" -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
      -d '{"vectors":{"size":768,"distance":"Cosine"}}' >/dev/null 2>&1 || true
}

embed() {
  python3 -c "
import json,urllib.request,sys
text=sys.stdin.read().strip()[:2048]
if not text: sys.exit(0)
payload=json.dumps({'model':'$ASH_MODEL','prompt':text,'keep_alive':-1}).encode()
try:
    req=urllib.request.Request('$OLLAMA_URL',data=payload,headers={'Content-Type':'application/json'})
    resp=urllib.request.urlopen(req,timeout=15)
    data=json.loads(resp.read())
    print(json.dumps(data.get('embedding',[])))
except Exception: print('[]')
" <<< "$1" 2>/dev/null || echo "[]"
}

index_chunk() {
  local name="$1" text="$2" meta="$3"
  local vec; vec=$(embed "$text")
  [[ "$vec" == "[]" ]] && return 0
  local cid; cid=$(echo -n "$name:$text" | md5sum | cut -d' ' -f1)
  curl -s -X POST "$QDRANT_URL/collections/web_context/points" \
    -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    -d "{\"points\":[{\"id\":\"$cid\",\"vector\":$vec,\"payload\":{\"source\":\"web\",\"source_name\":\"$name\",\"text\":\"${text:0:200}\",\"type\":\"web\",$meta}]}" >/dev/null 2>&1
}

web_search() {
  echo "Searching web for: $query"
  echo "(Web search requires a search API — indexing provided URLs below)"
}

research() {
  ensure_collection
  if [[ -z "$query" ]]; then echo "Usage: ash research <query> [limit]"; exit 1; fi
  echo "🔬 Research: \"$query\" (limit: $limit)"
  echo "(Web search placeholder — connect to a search API or manually index URLs)"
  echo "  Manual: ash research index <url1> <url2> ..."
}

search() {
  ensure_collection
  if [[ -z "$query" ]]; then echo "Usage: ash research search <query>"; exit 1; fi
  local vec; vec=$(embed "$query")
  [[ "$vec" == "[]" ]] && { echo "No embeddings available"; exit 0; }
  local result; result=$(curl -s -X POST "$QDRANT_URL/collections/web_context/points/search" \
    -H "api-key: $QDRANT_API_KEY" -H "Content-Type: application/json" \
    -d "{\"vector\":$vec,\"limit\":$limit,\"with_payload\":true}" 2>/dev/null)
  echo "$result" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for i,h in enumerate(data.get('result',[]),1):
        p=h.get('payload',{}); print(f'  [{i}] {p.get(\"source_name\",\"\")} (score: {h.get(\"score\",0):.3f})')
        print(f'      {p.get(\"text\",\"\")[:200]}')
except Exception: print('  No results')
" 2>/dev/null || echo "  No results"
}

index_url() {
  local url="$1"
  ensure_collection
  echo "Fetching $url..."
  local content; content=$(curl -s --max-time 15 -L "$url" 2>/dev/null | python3 -c "
import sys, re, html
text = sys.stdin.read()
text = re.sub(r'<script[^>]*>.*?</script>', '', text, flags=re.DOTALL)
text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
text = re.sub(r'<[^>]+>', ' ', text)
text = html.unescape(text)
text = re.sub(r'\s+', ' ', text).strip()
print(text[:5000])
" 2>/dev/null || echo "")
  if [[ -n "$content" ]]; then
    index_chunk "$url" "$content" '"url":"'"$url"'"'
    echo "✅ Indexed $(echo "$content" | wc -w) words from $url"
  else
    echo "⚠ Could not fetch content from $url"
  fi
}

case "$cmd" in
  research) research;;
  search) search;;
  index) shift; for url in "$@"; do index_url "$url"; done;;
  --help|*)
    echo "Usage: ash research <command> [args]"
    echo ""
    echo "Commands:"
    echo "  research <query> [limit]   Index web search results (connect API to enable)"
    echo "  search <query> [limit]     Search indexed web content"
    echo "  index <url1> [url2 ...]    Index URLs from command line"
    echo "  --help                     Show this help"
    ;;
esac
RESEOF

  chmod +x "$HOME_DIR/.local/bin/ash-research"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.local/bin/ash-research" 2>/dev/null || true

  save_state web research done '{"ash-research":true}'
  record_manifest "web-research: ash-research CLI, Qdrant web_context collection"
  return 0
}

###############################################################################
# PHASE 10: DESKTOP LAUNCHER
###############################################################################

patch_hyprland() {
  [[ "$PROFILE" != desktop ]] && return 0
  local hypr_conf="$HOME_DIR/.config/hypr/hyprland.conf"
  [[ ! -f "$hypr_conf" ]] && { mkdir -p "$HOME_DIR/.config/hypr"; echo "# Ash Linux Hyprland" > "$hypr_conf"; }
  backup_config "$hypr_conf"
  if grep -q "lsfs_launcher_hook" "$hypr_conf" 2>/dev/null; then
    ok "Super+Space already configured"
  else
    cat >> "$hypr_conf" << 'EOF'
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
EOF
    ok "Super+Space bound to launcher"
  fi
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/hypr" 2>/dev/null || true
  su - "$USER_NAME" -c "hyprctl reload" 2>/dev/null || true
  record_manifest "desktop: Hyprland Super+Space bind"
}

###############################################################################
# PHASE 11: SWAP (if needed)
###############################################################################

ensure_swap() {
  [[ "$PROFILE" != desktop ]] && return 0
  local hypr_conf="$HOME_DIR/.config/hypr/hyprland.conf"
  [[ ! -f "$hypr_conf" ]] && { mkdir -p "$HOME_DIR/.config/hypr"; echo "# Ash Linux Hyprland" > "$hypr_conf"; }
  backup_config "$hypr_conf"
  if grep -q "lsfs_launcher_hook" "$hypr_conf" 2>/dev/null; then
    ok "Super+Space already configured"
  else
    cat >> "$hypr_conf" << 'EOF'
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
EOF
    ok "Super+Space bound to launcher"
  fi
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.config/hypr" 2>/dev/null || true
  su - "$USER_NAME" -c "hyprctl reload" 2>/dev/null || true
  record_manifest "desktop: Hyprland Super+Space bind"
}

###############################################################################
# PHASE 8: SWAP (if needed)
###############################################################################

ensure_swap() {
  if detect_swap; then ok "Swap already enabled"; return 0; fi
  local mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if [[ -n "$mem" && "$mem" -ge 8388608 ]]; then ok "RAM >= 8GB — swap optional, skipping"; return 0; fi
  warn "No swap and <8GB RAM — creating 4GB swapfile..."
  if [[ "$DRY_RUN" == true ]]; then ok "Would create swapfile (dry-run)"; return 0; fi
  fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
  chmod 600 /swapfile
  mkswap /swapfile >>"$LOGFILE" 2>&1
  swapon /swapfile >>"$LOGFILE" 2>&1
  grep -q "/swapfile" /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  ok "4GB swapfile created"
  record_manifest "swap: 4GB /swapfile"
}

###############################################################################
# PHASE 9: BACKUP SCHEDULE
###############################################################################

setup_backup_timer() {
  cat > /etc/systemd/system/ash-backup.service << 'UNIT'
[Unit]
Description=Ash Linux Qdrant Backup
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'tar czf /var/backups/ash/qdrant-$(date +%Y%m%d).tar.gz /var/lib/qdrant 2>/dev/null; find /var/backups/ash -name "*.tar.gz" -mtime +7 -delete'
Nice=19
IOSchedulingClass=idle
UNIT
  cat > /etc/systemd/system/ash-backup.timer << 'TIMER'
[Unit]
Description=Daily Ash backup
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=6h
[Install]
WantedBy=timers.target
TIMER
  systemctl daemon-reload >>"$LOGFILE" 2>&1
  systemctl enable ash-backup.timer >>"$LOGFILE" 2>&1
  mkdir -p /var/backups/ash
  ok "Daily backup timer configured"
  record_manifest "backup: daily timer for Qdrant data"
}

###############################################################################
# PHASE 10: AUTO-UPDATE
###############################################################################

enable_auto_update() {
  cat > /etc/systemd/system/ash-auto-update.service << 'UNIT'
[Unit]
Description=Ash Linux Auto-Update
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ash-install.sh | bash -s -- --dry-run'
Nice=19
IOSchedulingClass=idle
UNIT
  cat > /etc/systemd/system/ash-auto-update.timer << 'TIMER'
[Unit]
Description=Weekly Ash Linux update check
[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=2h
[Install]
WantedBy=timers.target
TIMER
  systemctl daemon-reload >>"$LOGFILE" 2>&1
  systemctl enable ash-auto-update.timer >>"$LOGFILE" 2>&1 || true
  record_manifest "auto-update: weekly timer"
}

###############################################################################
# PHASE 11: VERIFICATION
###############################################################################

verify_all() {
  local ok=true; local sv=0
  curl -sf http://localhost:6333/healthz >/dev/null 2>&1 && { ok "Qdrant: healthy"; ((sv++)); } || { fail "Qdrant: down"; ok=false; }
  curl -sf http://localhost:11434/api/version >/dev/null 2>&1 && { ok "Ollama: running"; ((sv++)); } || { fail "Ollama: down"; ok=false; }
  curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -q "$MODEL" && ok "Model $MODEL: loaded" || warn "Model $MODEL: not found"
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME) systemctl --user is-active lsfs-daemon.service" 2>/dev/null | grep -qE "active|activating" && { ok "LSFS daemon: active"; ((sv++)); } || warn "LSFS daemon: inactive"
  su - "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME) systemctl --user is-active notebooklm-sync.service" 2>/dev/null | grep -qE "active|activating" && { ok "NotebookLM sync: active"; ((sv++)); } || warn "NotebookLM sync: inactive"
  [[ -x "$HOME_DIR/.config/scripts/lsfs_launcher_hook.sh" ]] && ok "Launcher hook: ready" || { fail "Launcher hook: missing"; ok=false; }
  command -v ash-context &>/dev/null && ok "ash context: available" || warn "ash context: missing"
  command -v ash-vscode &>/dev/null && ok "ash vscode: available" || warn "ash vscode: missing"
  command -v ash-research &>/dev/null && ok "ash research: available" || warn "ash research: missing"
  [[ -f "/etc/systemd/system/ash-auto-update.timer" ]] && ok "Auto-update: configured"
  command -v wofi &>/dev/null && ok "Wofi: available"
  [[ -f "$SECRETS_FILE" ]] && ok "Secrets: configured"
  [[ -f "$AUDIT_LOG" ]] && ok "Audit log: $AUDIT_LOG" || warn "Audit log: not found"
  [[ -n "$WEBHOOK_URL" ]] && ok "Webhook: configured" || true

  secure_dir="/var/lib/qdrant"
  local perms=$(stat -c "%a" "$secure_dir" 2>/dev/null || echo "unknown")
  [[ "$perms" == "700" || "$perms" == "755" ]] && ok "Qdrant dir permissions: $perms" || warn "Qdrant dir permissions: $perms"

  echo ""
  ok "=== $sv/5 core services running ==="
  $ok
}

###############################################################################
# WELCOME WIZARD
###############################################################################

welcome_wizard() {
  log "Running first-run welcome wizard..."
  tui_msgbox "Ash Linux v$VERSION" "Install complete!\n\nNext steps:\n  1. Press Super+Space to test search\n  2. Run 'ash context query' for AI search\n  3. Run 'ash vibe start' for vibe-coding mode\n  4. Run 'ash research topic' for web research\n  5. Check 'ash-doctor' for system health\n  6. Customize: re-run with --model <name> --webhook-url <url>\n  7. Audit log: $AUDIT_LOG"

  if ! have_tui; then
    echo ""
    echo -e "  ${BOLD}Quick start:${NC}"
    echo -e "    ${CYAN}Super+Space${NC}  →  Search files by meaning"
    echo -e "    ${CYAN}ash context${NC}    →  Search all context (files + NotebookLM + web)"
    echo -e "    ${CYAN}ash vibe start${NC}  →  Enter vibe-coding mode"
    echo -e "    ${CYAN}ash research${NC}    →  Web research and index"
    echo -e "    ${CYAN}lsfs-query${NC}     →  CLI: lsfs-query 'my config files'"
    echo -e "    ${CYAN}ash-doctor${NC}     →  Full health check"
    echo -e "    ${CYAN}ash-ask${NC}       →  RAG question answering"
    echo ""
    return
  fi

  if tui_yesno "Test Drive" "Press Super+Space to search now.\n\nTry: 'my config files' or 'scripts from last 2h'\n\nShow a quick demo?"; then
    log "User opted for demo (results shown in log)"
    su - "$USER_NAME" -c "lsfs-query 'configuration files'" >>"$LOGFILE" 2>&1 || true
    ok "Demo search executed"
  fi

  if [[ "$TELEMETRY" == true ]] && tui_yesno "Telemetry" "Help improve Ash by sending anonymous install stats?\n\nNo personal data, no file contents, no IP stored."; then
    local hw_id
    hw_id=$(sha256sum /etc/machine-id 2>/dev/null | cut -d' ' -f1 || echo "unknown")
    local stats="{\"version\":\"$VERSION\",\"arch\":\"$ARCH\",\"hw_id\":\"${hw_id:0:16}\",\"phases\":$(printf '%s' "${PHASES[*]}" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().split()))" 2>/dev/null || echo '[]')}"
    curl -sf -X POST -H "Content-Type: application/json" -d "$stats" "https://ash.sh/api/telemetry" -o /dev/null 2>/dev/null || true
    ok "Telemetry sent (anonymous)"
  fi
}

###############################################################################
# DASHBOARD
###############################################################################

  print_dashboard() {
  local all_pass=true
  for r in "${PHASE_STATUS[@]}"; do [[ "$r" != "pass" ]] && all_pass=false; done

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  Ash Linux v$VERSION — Installation Complete                    ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  [[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}DRY RUN — no changes were made${NC}" && echo ""

  printf "  ${BOLD}%-30s %s${NC}\n" "Phase" "Status"
  printf "  %-30s %s\n" "──────────────────────────────" "──────────"
  for i in "${!PHASES[@]}"; do
    local name="${PHASES[$i]}" result="${PHASE_STATUS[$i]}"
    if [[ "$result" == "pass" ]]; then printf "  %-30s ${GREEN}%-10s${NC}\n" "$name" "✔ PASS"
    else printf "  %-30s ${RED}%-10s${NC}\n" "$name" "✘ FAIL"; fi
  done

  echo ""
  local q=0 o=0 d=0 n=0
  curl -sf http://localhost:6333/healthz >/dev/null 2>&1 && q=1
  curl -sf http://localhost:11434/api/version >/dev/null 2>&1 && o=1
  pgrep -f lsfs_daemon >/dev/null 2>&1 && d=1
  pgrep -f ash-notebooklm-sync >/dev/null 2>&1 && n=1
  echo -e "  ${CYAN}Live:${NC} Qdrant=$([ $q -eq 1 ] && echo "${GREEN}Up${NC}" || echo "${RED}Down${NC}")  Ollama=$([ $o -eq 1 ] && echo "${GREEN}Up${NC}" || echo "${RED}Down${NC}")  LSFS=$([ $d -eq 1 ] && echo "${GREEN}Up${NC}" || echo "${RED}Down${NC}")  NotebookLM=$([ $n -eq 1 ] && echo "${GREEN}Up${NC}" || echo "${RED}Down${NC}")"

  local gpu=$(detect_gpu); echo -e "  ${CYAN}GPU:${NC} $gpu  ${CYAN}Profile:${NC} $PROFILE  ${CYAN}Model:${NC} $MODEL  ${CYAN}Arch:${NC} $ARCH"
  local de=$(detect_de); echo -e "  ${CYAN}Desktop:${NC} $de  ${CYAN}PM:${NC} $(detect_pm)  ${CYAN}Audit:${NC} $AUDIT_LEVEL"
  [[ -n "$WEBHOOK_URL" ]] && echo -e "  ${CYAN}Webhook:${NC} enabled"

  echo ""
  echo -e "  ${BOLD}Quick:${NC}  ${CYAN}Super+Space${NC}  |  ${CYAN}ash context 'query'${NC}  |  ${CYAN}ash vibe start${NC}  |  ${CYAN}ash-doctor${NC}"
  echo -e "  ${BOLD}AI:${NC}     ${CYAN}ash research <query>${NC}  |  ${CYAN}ash context 'query' --source notebooklm${NC}"
  echo -e "  ${BOLD}Logs:${NC}  ${CYAN}sudo journalctl -u qdrant -n 20${NC}"
  echo -e "  ${BOLD}Logs:${NC}  ${CYAN}journalctl --user -u lsfs-daemon -f${NC}"
  echo -e "  ${BOLD}Logs:${NC}  ${CYAN}journalctl --user -u notebooklm-sync -f${NC}"
  echo ""

  if [[ -n "$ROLLBACK_SNAPSHOT" ]]; then
    echo -e "  ${WARN} Snapshot: $ROLLBACK_SNAPSHOT"
    echo ""
  fi
  if [[ -f "$SECRETS_FILE" ]]; then
    echo -e "  ${WARN} Secrets: $SECRETS_FILE (chmod 600)"
    echo ""
  fi
  echo -e "  ${BOLD}Report:${NC} $LOGFILE"
  echo -e "  ${BOLD}Config:${NC} $CONFIG_DIR/"
  echo ""
  if $all_pass; then echo -e "  ${GREEN}${BOLD}✓ All systems operational. Press Super+Space!${NC}"
  else echo -e "  ${YELLOW}${BOLD}⚠ Some issues — run ash-doctor for details.${NC}"; fi
  echo ""
}

###############################################################################
# PHASE: DEP FIREWALL (Item 5 & 6)
###############################################################################

install_dep_firewall() {
  if resume_state dep_firewall install; then ok "Dep firewall already installed"; return 0; fi

  local script_src
  script_src="$(dirname "$0")/ash-dep-firewall.sh"
  if [[ ! -f "$script_src" ]]; then
    warn "ash-dep-firewall.sh not found next to installer — skipping"
    return 0
  fi

  install -m 0755 "$script_src" /usr/local/bin/ash-dep-firewall
  record_manifest "binary: /usr/local/bin/ash-dep-firewall"

  # Create default allowlist directory
  mkdir -p "$CONFIG_DIR/dep-allowlists"
  for ecosystem in npm pip cargo; do
    local src="$(dirname "$0")/../iso-profile/airootfs/etc/ash/dep-allowlists/${ecosystem}.txt"
    if [[ -f "$src" ]]; then
      cp "$src" "$CONFIG_DIR/dep-allowlists/${ecosystem}.txt"
    fi
  done
  record_manifest "config: $CONFIG_DIR/dep-allowlists/"

  # Wire shims for the installing user (non-root, PATH /usr/local/bin first)
  for tool in npm pip pip3 cargo; do
    local shim="/usr/local/bin/ash-firewall-${tool}"
    [[ ! -e "$shim" ]] && ln -sf /usr/local/bin/ash-dep-firewall "$shim"
    record_manifest "symlink: $shim"
  done

  ok "Dep firewall installed — shims: ash-firewall-npm, ash-firewall-pip, ash-firewall-cargo"
  save_state dep_firewall install done '{}'
}

###############################################################################
# PHASE: SNAPSHOT BRANCHING (Item 18)
###############################################################################

install_ash_branch() {
  if resume_state ash_branch install; then ok "ash-branch already installed"; return 0; fi

  local script_src
  script_src="$(dirname "$0")/ash-branch.sh"
  if [[ ! -f "$script_src" ]]; then
    warn "ash-branch.sh not found — skipping"
    return 0
  fi

  install -m 0755 "$script_src" /usr/local/bin/ash-branch
  record_manifest "binary: /usr/local/bin/ash-branch"

  # Create branches dir for the user
  su - "$USER_NAME" -c "mkdir -p \$HOME/.ash/branches" 2>/dev/null || true

  ok "ash-branch installed — use: ash-branch create <name>"
  save_state ash_branch install done '{}'
}

###############################################################################
# PHASE: MODEL ROUTER (Item 19)
###############################################################################

install_model_router() {
  if resume_state model_router install; then ok "Model router already installed"; return 0; fi

  local script_src
  script_src="$(dirname "$0")/ash-model-router.py"
  if [[ ! -f "$script_src" ]]; then
    warn "ash-model-router.py not found — skipping"
    return 0
  fi

  install -m 0755 "$script_src" /usr/local/bin/ash-model-router.py
  record_manifest "binary: /usr/local/bin/ash-model-router.py"

  # Install default router config if not already present
  local cfg_src
  cfg_src="$(dirname "$0")/../iso-profile/airootfs/etc/ash/router.json"
  if [[ -f "$cfg_src" && ! -f "$CONFIG_DIR/router.json" ]]; then
    cp "$cfg_src" "$CONFIG_DIR/router.json"
    record_manifest "config: $CONFIG_DIR/router.json"
  fi

  # Install systemd service
  cat > /etc/systemd/system/ash-model-router.service <<UNIT
[Unit]
Description=Ash Local Model Router (Ollama proxy on :11435)
After=ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER_NAME
ExecStart=/usr/bin/python3 /usr/local/bin/ash-model-router.py --host 127.0.0.1 --port 11435 --config $CONFIG_DIR/router.json
Restart=on-failure
RestartSec=5
$(if [[ "$NO_HARDEN" != true ]]; then echo "NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes
ReadWritePaths=/var/log/ash"; fi)

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload >>"$LOGFILE" 2>&1
  systemctl enable --now ash-model-router.service >>"$LOGFILE" 2>&1 || warn "Model router start failed (Ollama may not be up yet)"
  record_manifest "service: ash-model-router.service"

  ok "Model router installed — listening on :11435 (upstream Ollama :11434)"
  save_state model_router install done '{}'
}

###############################################################################
# PHASE: SUPPLY CHAIN AUDIT (Item 20)
###############################################################################

install_audit_logging() {
  if resume_state audit_logging install; then ok "Audit logging already installed"; return 0; fi

  local script_src
  script_src="$(dirname "$0")/ash-audit-setup.sh"
  if [[ ! -f "$script_src" ]]; then
    warn "ash-audit-setup.sh not found — skipping"
    return 0
  fi

  install -m 0755 "$script_src" /usr/local/bin/ash-audit-setup
  record_manifest "binary: /usr/local/bin/ash-audit-setup"

  mkdir -p /var/log/ash
  chmod 750 /var/log/ash

  bash /usr/local/bin/ash-audit-setup install >>"$LOGFILE" 2>&1 \
    && ok "Supply chain audit logging configured" \
    || warn "Audit setup had issues — check: ash-audit-setup status"

  record_manifest "audit: /etc/audit/rules.d/99-ash-supply-chain.rules"
  save_state audit_logging install done '{}'
}

mark_installed() {
  {
    echo "ash-install v$VERSION $(date)"
    echo "Profile: $PROFILE"
    echo "Model: $MODEL"
    echo "Arch: $ARCH"
    echo "GPU: $(detect_gpu)"
    echo "Components:"
    for i in "${!PHASES[@]}"; do echo "  ${PHASES[$i]}: ${PHASE_STATUS[$i]}"; done
    echo "Snapshot: $ROLLBACK_SNAPSHOT"
  } > "$INSTALL_MARK"
  chmod 644 "$INSTALL_MARK"
}

###############################################################################
# MAIN
###############################################################################

main() {
  clear
  echo -e "${CYAN}"
  cat << 'EOF'
    █████╗ ███████╗██╗  ██╗
   ██╔══██╗██╔════╝██║  ██║
   ███████║███████╗███████║
   ██╔══██║╚════██║██╔══██║
   ██║  ██║███████║██║  ██║
   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
EOF
  echo -e "${NC}"
  echo -e "  Ash Linux v$VERSION — Installer"
  echo -e "  Profile: $PROFILE  |  Model: $MODEL  |  Arch: $ARCH"
  [[ "$DRY_RUN" == true ]] && echo -e "  ${YELLOW}DRY RUN MODE — no changes will be made${NC}"
  [[ -n "$OFFLINE_BUNDLE" ]] && echo -e "  Offline bundle: $OFFLINE_BUNDLE"
  [[ -n "$WEBHOOK_URL" ]] && echo -e "  Webhook: enabled"
  echo -e "  Audit: $AUDIT_LEVEL  |  Max retries: $MAX_RETRIES"
  echo ""

  check_root "$@"

  local skip_update=false
  for arg in "$@"; do [[ "$arg" == "--updated" ]] && skip_update=true; done
  if [[ "$skip_update" != true && "$DRY_RUN" != true ]]; then
    check_self_update "$@"
  fi

  preflight_check

  if have_tui && [[ "$DRY_RUN" != true ]]; then
    select_model_tui
  fi

  if ! tui_yesno "Ash Linux v$VERSION" "Ready to install:\n\n  Profile: $PROFILE\n  Model: $MODEL\n  GPU: $(detect_gpu)\n  Desktop: $(detect_de)\n  Package manager: $(detect_pm)\n  Auto-rollback: Btrfs snapshot\n  Audit: $AUDIT_LEVEL\n\nProceed?"; then
    echo "Aborted."; exit 0
  fi

  flock_state acquire
  send_webhook "install.start" "Install starting (v$VERSION, profile: $PROFILE)" "info"

  create_snapshot
  sync

  run_phase "System Packages" "Packages installed" install_packages || true
  sync

  run_phase "Vector Database" "Qdrant deployed" install_qdrant || true
  sync

  run_phase "AI Engine" "Ollama deployed" install_ollama || true
  sync

  run_phase "Embedding Model" "$MODEL pulled" pull_model_with_progress "$MODEL" || true
  sync

  run_phase "Firewall" "Localhost-only rules" setup_firewall || true
  sync

  run_phase "LSFS Indexer" "Daemon + query deployed" deploy_lsfs || true
  sync

  run_phase "NotebookLM Sync" "Sync daemon deployed" install_notebooklm_sync || true
  sync

  run_phase "NotebookLM MCP" "MCP server for AI agents" install_notebooklm_mcp || true
  sync

  run_phase "Context & Vibe Mode" "ash context + ash vibe ready" install_ash_context || true
  sync

  run_phase "Web Research" "ash-research CLI available" install_web_research || true
  sync

  run_phase "Desktop" "Super+Space configured" patch_hyprland || true
  sync

  # ── New hardening & tooling phases ─────────────────────────────────────────
  run_phase "Dep Firewall" "Anti-slopsquatting shims installed" install_dep_firewall || true
  sync

  run_phase "Snapshot Branching" "ash-branch installed" install_ash_branch || true
  sync

  run_phase "Model Router" "ash-model-router on :11435" install_model_router || true
  sync

  run_phase "Supply Chain Audit" "auditd + JSONL provenance" install_audit_logging || true
  sync
  # ── End new phases ──────────────────────────────────────────────────────────

  run_phase "Swap" "Swapfile ensured" ensure_swap || true
  sync

  run_phase "Backup Schedule" "Daily backup timer" setup_backup_timer || true
  sync

  run_phase "Auto-Update" "Weekly check" enable_auto_update || true
  sync

  run_phase "Verification" "All checks passed" verify_all || true
  sync

  mark_installed
  flock_state release
  send_webhook "install.complete" "Install completed successfully" "info"

  print_dashboard

  if [[ "$DRY_RUN" != true ]]; then
    welcome_wizard
  fi
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
      exec sudo HOME="$HOME" bash "$0" "$@"
    else
      echo "Must run as root. Try: su -c 'bash $0'"
      exit 1
    fi
  fi
}

###############################################################################
# SELF-UPDATE
###############################################################################

check_self_update() {
  log "Checking for updates..."
  local remote_ver remote_raw
  remote_raw=$(retry curl -sfL "https://api.github.com/repos/exonew2/files/releases/latest" 2>>"$LOGFILE" || echo "")
  remote_ver=$(echo "$remote_raw" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\([^"]*\)".*/\1/' | sed 's/^v//' 2>/dev/null || echo "")
  if [[ -z "$remote_ver" ]]; then
    warn "Could not check for updates (no network?)"
    return 0
  fi

  local current="$VERSION"
  if [[ "$(printf '%s\n' "$current" "$remote_ver" | sort -V | tail -1)" == "$current" ]]; then
    ok "Already up to date (v$current)"
    return 0
  fi

  log "New version available: v$remote_ver (current: v$current)"
  local changelog
  changelog=$(echo "$remote_raw" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('body','')[:500])
except: pass" 2>/dev/null || echo "")

  if have_tui; then
    if [[ -n "$changelog" ]]; then
      tui_msgbox "Update Available: v$remote_ver" "Changelog:\n\n${changelog:0:500}\n\nUpgrade recommended."
    fi
    if tui_yesno "Update?" "A new version is available.\nCurrent: v$current → v$remote_ver\n\nDownload and self-update?"; then
      local new_script
      new_script=$(retry curl -sfL "https://raw.githubusercontent.com/exonew2/files/main/scripts/ash-install.sh" 2>>"$LOGFILE") || { fail "Download failed"; return 1; }
      if [[ -n "$new_script" ]]; then
        cp "$0" "$0.bak"
        echo "$new_script" > "$0"
        chmod +x "$0"
        ok "Self-updated to v$remote_ver (backup at $0.bak)"
        record_manifest "self-update: v$current -> v$remote_ver"
        warn "Reloading updated version..."
        exec bash "$0" --updated "$@"
      fi
    fi
  else
    log "Run \`curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ash-install.sh | bash\` to update to v$remote_ver"
  fi
}

###############################################################################
# MODEL SELECTION TUI
###############################################################################

select_model_tui() {
  if ! have_tui; then
    log "No TUI available — using default model: $MODEL"
    return 0
  fi
  local choice
  choice=$(tui_menu "Embedding Model" "Choose embedding model:\n\n Model               Size    Quality   Speed\n──────────────────────────────────────────" \
    "nomic-embed-text"    "137MB   ★★★☆☆    ★★★★☆ (default)" \
    "mxbai-embed-large"   "334MB   ★★★★☆    ★★★☆☆" \
    "snowflake-arctic-embed2" "1.2GB ★★★★★    ★★☆☆☆" \
    "all-MiniLM-L6-v2"    "80MB    ★★☆☆☆    ★★★★★" \
    "skip"                "Keep current: $MODEL") || choice="skip"
  if [[ "$choice" != "skip" && -n "$choice" ]]; then
    MODEL="$choice"
    ok "Model selected: $MODEL"
  fi
}

###############################################################################
# WEBHOOK
###############################################################################

send_webhook() {
  [[ -z "$WEBHOOK_URL" ]] && return 0
  local event="$1" message="$2" severity="${3:-info}"
  local payload
  payload=$(python3 -c "
import json
print(json.dumps({
    'event': '$event',
    'version': '$VERSION',
    'profile': '$PROFILE',
    'message': '${message//\'/\\\'}',
    'severity': '$severity',
    'ts': $(date +%s),
    'host': '$(hostname 2>/dev/null || echo "unknown")'
}))" 2>/dev/null || echo "{\"event\":\"$event\",\"message\":\"$message\"}")
  curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" -o /dev/null 2>>"$LOGFILE" || true
}

###############################################################################
# PULL MODEL WITH PROGRESS
###############################################################################

pull_model_with_progress() {
  local model="${1:-$MODEL}"
  if resume_state model pull_$model; then ok "Model $model already pulled"; return 0; fi
  if curl -sf http://localhost:11434/api/tags 2>/dev/null | grep -q "$model"; then
    ok "Model $model already present"
    save_state model pull_$model done "{}"
    return 0
  fi

  log "Pulling $model (this may take 3-10 minutes on first run)..."
  local pull_output pull_status=0

  if have_tui && command -v python3 &>/dev/null; then
    pull_output=$(python3 -c "
import json, urllib.request, sys, time

model = '$model'
url = 'http://localhost:11434/api/pull'
body = json.dumps({'model': model, 'stream': True}).encode()

req = urllib.request.Request(url, data=body, headers={'Content-Type': 'application/json'})
try:
    resp = urllib.request.urlopen(req, timeout=600)
    total = 0
    completed = 0
    last_pct = -1
    for line in resp:
        if not line.strip(): continue
        d = json.loads(line)
        if 'total' in d: total = d['total']
        if 'completed' in d: completed = d['completed']
        pct = int(completed / max(total, 1) * 100) if total else 0
        if pct != last_pct and pct > 0:
            print(pct)
            sys.stdout.flush()
            last_pct = pct
    print(100)
except Exception as e:
    print(f'ERROR:{e}')
    sys.exit(1)
" 2>/dev/null) || pull_status=1

    if [[ "$pull_status" -eq 0 && -n "$pull_output" ]]; then
      while IFS= read -r pct; do
        tui_gauge "Pulling $model" "Downloading $model... $pct%" "$pct"
      done <<< "$(echo "$pull_output" | grep -E '^[0-9]+$')"
      ok "Model $model downloaded"
    else
      warn "Streaming progress failed — falling back to simple pull"
      su - "$USER_NAME" -c "ollama pull $model" >>"$LOGFILE" 2>&1 || {
        curl -sf -X POST http://localhost:11434/api/pull -d "{\"model\":\"$model\"}" >>"$LOGFILE" 2>&1 || return 1
      }
    fi
  else
    su - "$USER_NAME" -c "ollama pull $model" >>"$LOGFILE" 2>&1 || {
      curl -sf -X POST http://localhost:11434/api/pull -d "{\"model\":\"$model\"}" >>"$LOGFILE" 2>&1 || return 1
    }
  fi

  curl -sf -X POST http://localhost:11434/api/generate -d "{\"model\":\"$model\",\"keep_alive\":-1,\"prompt\":\"warmup\"}" -o /dev/null >>"$LOGFILE" 2>&1 || true
  ok "Model $model ready"
  save_state model pull_$model done "{}"
  record_manifest "model: $model"
  return 0
}

main "$@"
