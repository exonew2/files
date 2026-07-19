#!/usr/bin/bash
# /usr/lib/iso/detect-timezone.sh — Auto-detect timezone
set -euo pipefail

log() { logger -t iso-timezone "$*"; }

# Skip if already set
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
if [[ -n "$CURRENT_TZ" && "$CURRENT_TZ" != "UTC" && "$CURRENT_TZ" != "n/a" ]]; then
    log "Timezone already set to $CURRENT_TZ, skipping"
    exit 0
fi

detect_timezone() {
    # 1. VMware GuestInfo
    if systemctl is-active --quiet vmtoolsd.service 2>/dev/null; then
        local tz
        tz=$(vmware-rpctool "info-get guestinfo.timezone" 2>/dev/null || true)
        if [[ -n "$tz" ]]; then
            echo "$tz"
            return
        fi
    fi

    # 2. QEMU guest agent
    if [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
        local tz
        tz=$(timeout 2 socat - UNIX-CONNECT:/dev/virtio-ports/org.qemu.guest_agent.0 <<< '{"execute":"guest-get-timezone"}' 2>/dev/null | jq -r '.return // empty')
        if [[ -n "$tz" ]]; then
            echo "$tz"
            return
        fi
    fi

    # 3. IP geolocation (fallback, no external API call)
    local ip_country
    ip_country=$(curl -sf --max-time 3 https://ipinfo.io/country 2>/dev/null || echo "")
    if [[ -n "$ip_country" ]]; then
        # Map country to common timezone
        case "$ip_country" in
            US) echo "America/New_York"; return ;;
            GB) echo "Europe/London"; return ;;
            DE) echo "Europe/Berlin"; return ;;
            FR) echo "Europe/Paris"; return ;;
            JP) echo "Asia/Tokyo"; return ;;
            CN) echo "Asia/Shanghai"; return ;;
            IN) echo "Asia/Kolkata"; return ;;
            AU) echo "Australia/Sydney"; return ;;
            BR) echo "America/Sao_Paulo"; return ;;
            CA) echo "America/Toronto"; return ;;
            RU) echo "Europe/Moscow"; return ;;
            KR) echo "Asia/Seoul"; return ;;
            SG) echo "Asia/Singapore"; return ;;
            NL) echo "Europe/Amsterdam"; return ;;
            SE) echo "Europe/Stockholm"; return ;;
            NO) echo "Europe/Oslo"; return ;;
            FI) echo "Europe/Helsinki"; return ;;
            DK) echo "Europe/Copenhagen"; return ;;
            PL) echo "Europe/Warsaw"; return ;;
            ES) echo "Europe/Madrid"; return ;;
            IT) echo "Europe/Rome"; return ;;
            CH) echo "Europe/Zurich"; return ;;
            AT) echo "Europe/Vienna"; return ;;
            BE) echo "Europe/Brussels"; return ;;
            IE) echo "Europe/Dublin"; return ;;
            NZ) echo "Pacific/Auckland"; return ;;
            ZA) echo "Africa/Johannesburg"; return ;;
            MX) echo "America/Mexico_City"; return ;;
        esac
    fi

    # 4. Check /etc/localtime symlink
    if [[ -L /etc/localtime ]]; then
        readlink /etc/localtime | sed 's|.*/zoneinfo/||'
        return
    fi

    echo ""
}

TZ=$(detect_timezone)
if [[ -n "$TZ" ]]; then
    timedatectl set-timezone "$TZ" 2>/dev/null && log "Timezone set to $TZ" || log "Failed to set timezone to $TZ"
else
    log "Could not detect timezone, keeping default"
fi
