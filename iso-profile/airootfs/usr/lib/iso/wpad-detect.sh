#!/usr/bin/bash
# /usr/lib/iso/wpad-detect.sh
set -euo pipefail

# Try DHCP option 252 first
WPAD_URL=$(busctl call org.freedesktop.network1 /org/freedesktop/network1 org.freedesktop.DBus.Properties Get string:org.freedesktop.network1.Link string:DHCPv4Option252 2>/dev/null | awk -F'"' '{print $2}')

if [[ -z "$WPAD_URL" ]]; then
    # Try DNS WPAD
    SEARCH_DOMAIN=$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}' | head -1)
    [[ -n "$SEARCH_DOMAIN" ]] && WPAD_URL="http://wpad.$SEARCH_DOMAIN/wpad.dat"
fi

if [[ -n "$WPAD_URL" ]]; then
    curl -sf --max-time 5 "$WPAD_URL" -o /etc/wpad.dat && \
    echo "export http_proxy=\$(grep -i '^PROXY' /etc/wpad.dat | head -1 | sed 's/.*PROXY *//; s/;.*//')" > /etc/profile.d/wpad.sh && \
    echo "export https_proxy=\$http_proxy" >> /etc/profile.d/wpad.sh && \
    chmod +x /etc/profile.d/wpad.sh
fi