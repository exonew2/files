#!/usr/bin/bash
# /usr/lib/iso/grub-btrfs-setup.sh
set -euo pipefail

pacman -U --noconfirm /usr/share/iso-packages/grub-btrfs-*.pkg.tar.zst 2>/dev/null || true

mkdir -p /etc/grub-btrfs
cat > /etc/grub-btrfs/config <<'EOF'
GRUB_BTRFS_SUBMENUNAME="Btrfs Snapshots"
GRUB_BTRFS_SHOW_SNAPSHOTS_FOUND="true"
GRUB_BTRFS_MAX_KERNELS=3
GRUB_BTRFS_MAX_SNAPSHOTS=10
EOF

systemctl enable --now grub-btrfsd.service grub-btrfs.path