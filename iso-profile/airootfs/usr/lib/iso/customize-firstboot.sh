#!/usr/bin/env bash
# /usr/lib/iso/customize-firstboot.sh — User customization from config drive/USB/GuestInfo

set -euo pipefail

log() { logger -t iso-customize "$*"; }

# 1. Config drive (OpenStack/CloudStack style)
CONFIG_DRIVE=$(blkid -L CONFIG 2>/dev/null || blkid -L config-2 2>/dev/null || true)
if [[ -n "$CONFIG_DRIVE" ]]; then
    mkdir -p /mnt/config
    mount -o ro "$CONFIG_DRIVE" /mnt/config 2>/dev/null || true
    if [[ -f /mnt/config/user-data ]]; then
        /usr/lib/iso/process-cloud-config.sh /mnt/config/user-data
    fi
    umount /mnt/config 2>/dev/null || true
fi

# 2. USB stick labeled ISO-CONFIG
USB_DRIVE=$(blkid -L ISO-CONFIG 2>/dev/null || true)
if [[ -n "$USB_DRIVE" ]]; then
    mkdir -p /mnt/usb
    mount -o ro "$USB_DRIVE" /mnt/usb 2>/dev/null || true
    if [[ -f /mnt/usb/user-data.yaml ]]; then
        /usr/lib/iso/process-cloud-config.sh /mnt/usb/user-data.yaml
    fi
    umount /mnt/usb 2>/dev/null || true
fi

# 3. VMware GuestInfo
if systemctl is-active --quiet vmtoolsd.service 2>/dev/null; then
    USERDATA=$(vmware-rpctool "info-get guestinfo.userdata" 2>/dev/null || echo "")
    if [[ -n "$USERDATA" ]]; then
        echo "$USERDATA" | /usr/lib/iso/process-cloud-config.sh /dev/stdin
    fi
fi

# 4. QEMU fw_cfg / virtio-serial
if [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; then
    timeout 5 socat - UNIX-CONNECT:/dev/virtio-ports/org.qemu.guest_agent.0 <<< '{"execute":"guest-get-fwcfg", "arguments":{"name":"opt/com.coreos/config", "size":1048576}}' 2>/dev/null | \
    jq -r '.return.data // empty' 2>/dev/null | base64 -d 2>/dev/null | /usr/lib/iso/process-cloud-config.sh /dev/stdin || true
fi

log "Customization complete"