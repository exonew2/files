#!/usr/bin/bash
# /usr/lib/iso/btrfs-maintenance.sh — Btrfs trim, dedup, and balance
set -euo pipefail

log() { logger -t btrfs-maintenance "$*"; }

# 1. TRIM (discard unused blocks)
log "Running fstrim..."
fstrim -av || log "fstrim skipped (not supported)"

# 2. Filesystem balance (only if fragmentation > 20%)
USAGE=$(btrfs filesystem usage / -b 2>/dev/null | grep -oP 'Unallocated:\s+\K[\d.]+' || echo "0")
TOTAL=$(btrfs filesystem usage / -b 2>/dev/null | grep -oP 'Device size:\s+\K[\d.]+' || echo "1")
FRAG_PCT=$(awk "BEGIN {printf \"%.0f\", (1 - $USAGE/$TOTAL) * 100}")
if [[ "$FRAG_PCT" -gt 20 ]]; then
    log "Fragmentation at ${FRAG_PCT}% — running balance..."
    btrfs balance start -dusage=50 -dlimit=2 / || log "balance skipped"
fi

# 3. Dedup with duperemove if available
if command -v duperemove &>/dev/null; then
    log "Running duperemove on /home..."
    duperemove -dr --hashfile=/var/cache/duperemove-hash /home 2>&1 | logger -t btrfs-maintenance || true
fi

log "Btrfs maintenance complete"
