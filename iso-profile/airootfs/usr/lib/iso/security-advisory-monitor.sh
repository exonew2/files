#!/usr/bin/env bash
# /usr/lib/iso/security-advisory-monitor.sh
# Check Arch Linux security advisories against installed packages
# Run via timer: systemd-timer weekly

set -euo pipefail

ADVISORY_URL="https://security.archlinux.org/all.json"
CACHE_FILE="/var/cache/iso-security-advisories.json"
CACHE_TTL=86400
OUTPUT=""

log() { logger -t iso-security "$*"; }

# Fetch advisories (with cache)
if [[ -f "$CACHE_FILE" ]]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if [[ $AGE -gt $CACHE_TTL ]]; then
        curl -sf --max-time 30 "$ADVISORY_URL" -o "$CACHE_FILE" || true
    fi
else
    mkdir -p "$(dirname "$CACHE_FILE")"
    curl -sf --max-time 30 "$ADVISORY_URL" -o "$CACHE_FILE" || true
fi

if [[ ! -f "$CACHE_FILE" ]]; then
    log "Failed to fetch advisory list"
    exit 0
fi

# Parse advisories and check against installed packages
AFFECTED=0
while IFS= read -r advisory; do
    PKG=$(echo "$advisory" | jq -r '.package // empty')
    SEVERITY=$(echo "$advisory" | jq -r '.severity // "unknown"')
    STATUS=$(echo "$advisory" | jq -r '.status // empty')
    
    [[ -z "$PKG" || "$STATUS" != "fixed" ]] && continue
    
    if pacman -Qi "$PKG" &>/dev/null; then
        INSTALLED=$(pacman -Qi "$PKG" | grep '^Version' | awk '{print $3}')
        ADVISORY_VERSION=$(echo "$advisory" | jq -r '.fixed_version // ""')
        
        log "VULNERABLE: $PKG ($INSTALLED < $ADVISORY_VERSION) - $SEVERITY"
        AFFECTED=$((AFFECTED + 1))
        OUTPUT="$OUTPUT\n- $PKG ($INSTALLED) needs upgrade to $ADVISORY_VERSION [$SEVERITY]"
    fi
done < <(jq -c '.[]' "$CACHE_FILE" 2>/dev/null || echo "")

if [[ $AFFECTED -gt 0 ]]; then
    notify-send -u critical "Security Advisories" \
        "$AFFECTED packages have known vulnerabilities:\n$OUTPUT\n\nRun: sudo pacman -Syu" \
        --icon=dialog-warning
fi

log "Security check complete: $AFFECTED vulnerable packages found"
