#!/usr/bin/bash
# /usr/lib/iso/qdrant-setup.sh
set -euo pipefail

btrfs subvolume show /var/lib/qdrant >/dev/null 2>&1 || btrfs subvolume create /var/lib/qdrant
chown qdrant:qdrant /var/lib/qdrant
snapper -c root set-config EXCLUDE_PATHS="/var/lib/qdrant" 2>/dev/null || true