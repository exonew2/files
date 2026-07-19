#!/usr/bin/bash
# /usr/lib/iso/detect-gpu.sh — Detect and load GPU drivers
set -euo pipefail

log() { logger -t iso-detect-gpu "$*"; }

detect_gpu() {
    local vendor
    vendor=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | grep -oP '\[\K[0-9a-fA-F]{4}:[0-9a-fA-F]{4}' || echo "unknown")
    case "$vendor" in
        *1002*|*amd*|*AMD*)
            echo "amd"
            ;;
        *8086*|*intel*|*Intel*)
            echo "intel"
            ;;
        *10de*|*nvidia*|*NVIDIA*)
            echo "nvidia"
            ;;
        *1ab6*)
            echo "virtio-gpu"
            ;;
        *15ad*)
            echo "vmware"
            ;;
        *80ee*)
            echo "vbox"
            ;;
        *1b36*|*1af4*)
            echo "qemu"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

GPU=$(detect_gpu)
log "Detected GPU: $GPU"

case "$GPU" in
    amd)
        modprobe amdgpu 2>/dev/null || modprobe radeon 2>/dev/null || true
        echo "amd" > /etc/iso-gpu-driver
        log "Loaded AMD driver"
        ;;
    intel)
        modprobe i915 2>/dev/null || true
        echo "intel" > /etc/iso-gpu-driver
        log "Loaded Intel driver"
        ;;
    nvidia)
        modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm 2>/dev/null || true
        echo "nvidia" > /etc/iso-gpu-driver
        log "Loaded NVIDIA driver"
        if [[ -d /proc/driver/nvidia ]]; then
            echo "NVIDIA proprietary driver active"
        fi
        ;;
    vmware)
        modprobe vmwgfx 2>/dev/null || true
        echo "vmware" > /etc/iso-gpu-driver
        log "Loaded VMware SVGA driver"
        ;;
    vbox)
        modprobe vboxvideo 2>/dev/null || true
        echo "vbox" > /etc/iso-gpu-driver
        log "Loaded VirtualBox video driver"
        ;;
    qemu|virtio-gpu)
        modprobe virtio_gpu 2>/dev/null || modprobe qxl 2>/dev/null || true
        echo "virtio" > /etc/iso-gpu-driver
        log "Loaded VirtIO/QXL GPU driver"
        ;;
    *)
        log "Unknown GPU, falling back to modesetting"
        echo "modesetting" > /etc/iso-gpu-driver
        ;;
esac

# Output for Hyprland config generation
echo "$GPU"
