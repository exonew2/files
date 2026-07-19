#!/usr/bin/bash
# /usr/lib/iso/disable-unnecessary.sh — Mask slow/unnecessary services
set -euo pipefail

log() { logger -t iso-optimize "$*"; }

MASK_LIST=(
    systemd-networkd-wait-online.service  # blocks boot waiting for network
    pkgfile-update.timer                   # pkgfile database sync (slow)
    systemd-resolved.service               # resolved already configured
    whoopsie.service                        # Ubuntu crash reporting (not needed)
    avahi-daemon.service                    # mDNS not critical for VM boot
    man-db.timer                            # man-db rebuild (slow)
    updatedb.timer                          # locate db update (slow)
    uuidd.socket                            # UUID generation socket (rarely used)
)

for svc in "${MASK_LIST[@]}"; do
    if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
        systemctl mask --now "$svc" 2>/dev/null && log "Masked: $svc" || true
    fi
done

# Parallelize service start
mkdir -p /etc/systemd/system/getty.target.wants
mkdir -p /etc/systemd/system/sshd.socket.d
cat > /etc/systemd/system/sshd.socket.d/50-parallel.conf <<'EOF'
[Socket]
ListenStream=
ListenStream=22
FreeBind=yes
EOF

log "Service optimization complete"
