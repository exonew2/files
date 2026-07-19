#!/usr/bin/env bash
# /usr/lib/iso/hyprland-setup.sh
# Runs at each Hyprland startup to ensure proper runtime configuration.
# Detects GPU, VM, display setup, and applies runtime fixes.

set -euo pipefail

log() { logger -t hyprland-setup "$*"; }
CONFIG_DIR="$HOME/.config/hypr"
ENV_DIR="$CONFIG_DIR/env"

mkdir -p "$ENV_DIR"

# 1. GPU detection
if [[ -x "$CONFIG_DIR/scripts/gpu-detect.sh" ]]; then
  "$CONFIG_DIR/scripts/gpu-detect.sh"
else
  /usr/lib/iso/hyprland-gpu-detect.sh
fi

# 2. VM clipboard workarounds
if systemd-detect-virt --vm --quiet 2>/dev/null; then
  log "VM detected — applying clipboard workarounds"

  # VMware: ensure vmware-user runs for clipboard
  if command -v vmware-user &>/dev/null; then
    vmware-user 2>/dev/null || true
  fi

  # VirtualBox: VBoxClient clipboard
  if command -v VBoxClient &>/dev/null; then
    VBoxClient --clipboard 2>/dev/null || true
  fi

  # SPICE: vdagent for clipboard + display
  if command -v spice-vdagent &>/dev/null; then
    spice-vdagent 2>/dev/null || true
  fi

  # QEMU guest agent
  if command -v qemu-ga &>/dev/null; then
    systemctl --user enable --now qemu-guest-agent.service 2>/dev/null || true
  fi

  # wl-clipboard fallback: ensure persistence server runs
  if command -v wl-paste &>/dev/null; then
    wl-paste --watch cliphist store 2>/dev/null &
  fi
fi

# 3. Display resolution detection for VMs
if systemd-detect-virt --vm --quiet 2>/dev/null; then
  # Try to set a reasonable default resolution via hyprctl if monitor is small
  MONITOR_INFO=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].width' 2>/dev/null || echo "0")
  if [[ "$MONITOR_INFO" -lt 1024 ]] 2>/dev/null; then
    log "Small display detected ($MONITOR_INFO px) — forcing 1920x1080"
    hyprctl keyword monitor ",1920x1080@60,auto,1" 2>/dev/null || true
  fi
fi

# 4. Set wallpaper (fallback if hyprpaper hasn't loaded yet)
sleep 1
if command -v hyprpaper &>/dev/null; then
  hyprctl hyprpaper wallpaper ",/usr/share/backgrounds/default.png" 2>/dev/null || true
fi

# 5. Ensure correct Wayland environment
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

log "Hyprland runtime setup complete"
