#!/usr/bin/bash
# /usr/lib/iso/boot-optimize.sh — Boot time optimization script
# Profiles services with systemd-analyze blame and masks top offenders.
set -euo pipefail

log() { logger -t boot-optimize "$*"; }

log "Running boot optimization analysis..."

# 1. Identify top-5 slowest services from current boot
SLOW_SERVICES=$(systemd-analyze blame 2>/dev/null | head -5 || true)
if [[ -n "$SLOW_SERVICES" ]]; then
    log "Top 5 slowest services:"
    echo "$SLOW_SERVICES" | while IFS= read -r line; do log "  $line"; done

    # Extract service names and create drop-ins for known slow ones
    echo "$SLOW_SERVICES" | grep -oP '\S+\.service' | while IFS= read -r svc; do
        case "$svc" in
            systemd-journal-flush.service|systemd-tmpfiles-setup-dev.service|systemd-sysctl.service|systemd-modules-load.service|systemd-udev-trigger.service|systemd-udev-settle.service)
                log "  System service (cannot mask): $svc"
                ;;
            *)
                if systemctl is-enabled "$svc" &>/dev/null && ! systemctl is-active "$svc" &>/dev/null; then
                    log "  Masking slow service: $svc"
                    systemctl mask "$svc" 2>/dev/null || true
                fi
                ;;
        esac
    done
fi

# 2. Apply runtime optimizations
# Reduce udev settle timeout
mkdir -p /etc/systemd/system/systemd-udev-settle.service.d
cat > /etc/systemd/system/systemd-udev-settle.service.d/50-timeout.conf <<'EOF'
[Service]
TimeoutSec=5
EOF

# Parallelize udev
udevadm control --max-children=256 2>/dev/null || true

# Disable plymouth if present (not needed for fast boot)
systemctl mask plymouth-start.service plymouth-read-write.service plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true

# 3. Pre-disable known slow services common in VM boots
MASK_LIST=(
    systemd-udev-settle.service
)
for svc in "${MASK_LIST[@]}"; do
    if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
        systemctl mask --now "$svc" 2>/dev/null && log "Masked: $svc" || true
    fi
done

# 4. Optimize systemd-journal flush — volatile journal means no flush needed
if systemctl is-enabled systemd-journal-flush.service &>/dev/null; then
    systemctl mask systemd-journal-flush.service 2>/dev/null || true
    log "Masked systemd-journal-flush.service (volatile journal)"
fi

log "Boot optimization complete"
