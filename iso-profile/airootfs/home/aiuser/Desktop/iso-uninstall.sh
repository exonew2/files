#!/usr/bin/bash
# /home/aiuser/Desktop/iso-uninstall.sh
set -euo pipefail

detect_platform() {
    case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
        *VMware*) echo "vmware" ;;
        *VirtualBox*) echo "virtualbox" ;;
        *Parallels*) echo "parallels" ;;
        *UTM*) echo "utm" ;;
        *QEMU*|*KVM*) echo "qemu" ;;
        *) echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)
VM_NAME=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | tr '[:upper:]' '[:lower:]' || hostname)

case "$PLATFORM" in
    vmware)
        command -v vmrun >/dev/null && (vmrun -T ws deleteVM "$VM_NAME" 2>/dev/null || vmrun -T fusion deleteVM "$VM_NAME" 2>/dev/null || true)
        ;;
    virtualbox)
        command -v VBoxManage >/dev/null && VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
        ;;
    parallels)
        command -v prlctl >/dev/null && prlctl unregister "$VM_NAME" --delete 2>/dev/null || true
        ;;
    utm)
        command -v utmctl >/dev/null && utmctl delete "$VM_NAME" 2>/dev/null || true
        ;;
    qemu)
        command -v virsh >/dev/null && virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        ;;
esac

# Remove host port forwards
for port in 2222 11434 6333 6334; do
    sudo ufw delete allow $port 2>/dev/null || true
    sudo firewall-cmd --permanent --remove-port=$port/tcp 2>/dev/null || true
done

notify-send "ISO AI VM" "Uninstall complete. You can now delete this VM." --icon=dialog-information