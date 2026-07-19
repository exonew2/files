#!/usr/bin/bash
# /usr/lib/iso/auto-update.sh
set -euo pipefail

# Create pre-update snapshot
PRE_NUM=$(snapper -c root create --type pre --description "Auto-update: $(date '+%Y-%m-%d %H:%M')" --userdata "type=auto-update" --cleanup-algorithm=number | grep -o '[0-9]\+')

# Update
pacman -Syu --noconfirm

# Create post-update snapshot
snapper -c root create --type post --pre-number "$PRE_NUM" --description "Auto-update: $(date '+%Y-%m-%d %H:%M')" --cleanup-algorithm=number