#!/usr/bin/bash
# /usr/lib/iso/detect-keyboard.sh — Auto-detect keyboard layout
set -euo pipefail

log() { logger -t iso-keyboard "$*"; }

# Skip if already set by user
CURRENT_KB=$(localectl status --no-pager 2>/dev/null | grep 'Keymap' | awk '{print $3}' || echo "")
if [[ -n "$CURRENT_KB" && "$CURRENT_KB" != "us" ]]; then
    log "Keyboard layout already set to $CURRENT_KB, skipping"
    exit 0
fi

detect_keyboard() {
    # 1. Check DMI product name for VM hints
    local product
    product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    case "$product" in
        *VMware*|*VirtualBox*|*QEMU*|*KVM*|*Parallels*|*UTM*)
            # VM hosts usually pass through host keyboard, but safe default
            ;;
    esac

    # 2. Check for X11 keymap from display server
    if command -v setxkbmap &>/dev/null && DISPLAY=:0 setxkbmap -query 2>/dev/null | grep -q 'layout'; then
        local xkb_layout
        xkb_layout=$(DISPLAY=:0 setxkbmap -query 2>/dev/null | grep 'layout' | awk '{print $2}')
        if [[ -n "$xkb_layout" ]]; then
            echo "$xkb_layout"
            return
        fi
    fi

    # 3. Check /etc/vconsole.conf
    if [[ -f /etc/vconsole.conf ]]; then
        local vc_layout
        vc_layout=$(grep '^KEYMAP=' /etc/vconsole.conf | cut -d= -f2)
        if [[ -n "$vc_layout" ]]; then
            echo "$vc_layout"
            return
        fi
    fi

    # 4. VM console default
    local product_name
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    case "$product_name" in
        *VMware*|*VirtualBox*|*QEMU*|*KVM*|*Parallels*)
            # Most VM users are on US or localized keyboard
            echo "us"
            return
            ;;
    esac

    # 5. No detection possible, default to us
    echo "us"
}

KB=$(detect_keyboard)
if [[ -n "$KB" ]]; then
    localectl set-keymap "$KB" 2>/dev/null && log "Keyboard layout set to $KB" || log "Failed to set keyboard layout to $KB"
    # Also set X11 layout
    if command -v localectl &>/dev/null; then
        localectl set-x11-keymap "$KB" 2>/dev/null || true
    fi
fi

# Apply to Hyprland config if present
HYPR_CONF="/home/aiuser/.config/hypr/hyprland.conf"
if [[ -f "$HYPR_CONF" ]]; then
    sed -i "s/kb_layout = .*/kb_layout = $KB/" "$HYPR_CONF" 2>/dev/null || true
    log "Updated Hyprland keyboard layout to $KB"
fi
