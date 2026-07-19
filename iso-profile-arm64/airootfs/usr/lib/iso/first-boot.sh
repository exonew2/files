#!/usr/bin/bash
# /usr/lib/iso/first-boot.sh
set -euo pipefail

log() { logger -t iso-firstboot "$*"; }

log "Starting ISO first-boot setup"

# 1. Auto-detect timezone (VM guest info, IP geo, fallback)
/usr/lib/iso/detect-timezone.sh

# 2. Auto-detect keyboard layout
/usr/lib/iso/detect-keyboard.sh

# 3. Create aiuser, passwordless sudo, autologin
systemd-sysusers /usr/lib/sysusers.d/iso-aiuser.conf
mkdir -p /etc/sudoers.d
echo 'aiuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/iso-aiuser

# 4. GNOME autologin on Wayland
mkdir -p /etc/gdm
cat > /etc/gdm/custom.conf <<'EOF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=aiuser
WaylandEnable=true
EOF

# 5. Disable GNOME initial setup
mkdir -p /etc/gnome-initial-setup
touch /etc/gnome-initial-setup/disabled

# 6. Generate SSH host and user keys
/usr/lib/iso/gen-ssh-keys.sh

# 7. Detect GPU and load kernel modules
/usr/lib/iso/detect-gpu.sh

GPU=$(cat /etc/iso-gpu-driver 2>/dev/null || echo modesetting)
/usr/lib/iso/gen-hyprland-config.sh "$GPU"

# 8. Boot optimization (masks slow services, applies runtime tuning)
systemctl enable --now iso-boot-optimize.service

# 9. Start ash-preload for instant app launch
systemctl enable --now iso-ash-preload.service

# 10. Compile dconf database for GNOME memory tuning
dconf update 2>/dev/null || true

# 11. Pull default Ollama model in background
systemctl start ollama-pull-default.service --no-block

# 12. Start Qdrant vector DB
systemctl enable --now qdrant.service qdrant.socket qdrant-grpc.socket

# 13. Enable SSH socket-activated
systemctl enable --now sshd.socket

# 14. Enable VM guest agents
systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service 2>/dev/null || true
systemctl enable --now vboxservice.service 2>/dev/null || true
systemctl enable --now qemu-guest-agent.service 2>/dev/null || true
systemctl enable --now spice-vdagentd.service 2>/dev/null || true

# 15. Setup Qdrant storage (Btrfs subvolume excluded from snapshots)
/usr/lib/iso/qdrant-setup.sh

# 16. Enable auto-update timer
systemctl enable --now iso-auto-update.timer

# 17. Enable VM network detection timer
systemctl enable --now update-vm-nftables.timer

# 18. Enable WPAD detection
systemctl enable --now wpad-detect.service

# 19. Enable grub-btrfs for snapshot boot entries
systemctl enable --now grub-btrfsd.service grub-btrfs.path 2>/dev/null || true

# 20. Enable Btrfs maintenance timer
systemctl enable --now iso-btrfs-maintenance.timer

# 21. Disable unnecessary services for boot speed
systemctl enable --now iso-disable-watchdog.service

# 22. Enable Ash Agentic OS user services for aiuser
loginctl enable-linger aiuser 2>/dev/null || true
runuser -u aiuser -- systemctl --user enable ash-agent.service 2>/dev/null || true
runuser -u aiuser -- systemctl --user enable ash-workspace.service 2>/dev/null || true
runuser -u aiuser -- systemctl --user enable ash-launcher.service 2>/dev/null || true

# 23. Enable security advisory monitor
systemctl enable --now iso-security-advisory.timer 2>/dev/null || true

# 24. Lock down SSH if we're past Packer provisioning
if [[ -f /etc/iso-packer-done ]]; then
    systemctl start iso-packer-auth.service
fi

# 25. Mark done
touch /etc/iso-firstboot-done
log "ISO first-boot setup complete"
