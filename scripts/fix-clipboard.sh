#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

echo -e "${CYAN}────────────────────────────────────────────${NC}"
echo -e "${CYAN}  VMware Clipboard Fix${NC}"
echo -e "${CYAN}────────────────────────────────────────────${NC}"

if ! systemd-detect-virt --vm 2>/dev/null | grep -qi vmware; then
    warn "Not running in a VMware VM — skipping"
    exit 0
fi

info "Installing open-vm-tools..."
sudo pacman -S --needed --noconfirm open-vm-tools 2>/dev/null || \
    warn "Package install had issues — try: sudo pacman -S open-vm-tools"

info "Enabling vmtoolsd.service..."
sudo systemctl enable --now vmtoolsd.service 2>/dev/null && ok "vmtoolsd started" || \
    warn "vmtoolsd failed to start"

info "Enabling vmware-vmblock-fuse.service..."
sudo systemctl enable --now vmware-vmblock-fuse.service 2>/dev/null && ok "vmware-vmblock-fuse started" || \
    warn "vmware-vmblock-fuse failed to start"

info "Adding vmware-user to Hyprland config..."
mkdir -p "$HOME/.config/hypr"
if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
    if ! grep -q "vmware-user" "$HOME/.config/hypr/hyprland.conf" 2>/dev/null; then
        echo "exec-once = vmware-user" >> "$HOME/.config/hypr/hyprland.conf"
        ok "vmware-user added to hyprland.conf"
    else
        ok "vmware-user already in hyprland.conf"
    fi
else
    cat > "$HOME/.config/hypr/hyprland.conf" << 'CONF'
exec-once = vmware-user
CONF
    ok "hyprland.conf created with vmware-user"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  VMware Clipboard Fix Applied                             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}⚠️  YOU MUST ALSO FIX THE WINDOWS HOST:${NC}"
echo -e "${YELLOW}================================================${NC}"
echo "1. On your Windows host, open:"
echo "   C:\\Users\\pc\\Documents\\Virtual Machines\\Windows 10\\Windows 10.vmx"
echo "2. Add these lines at the bottom:"
echo '   isolation.tools.copy.disable = "FALSE"'
echo '   isolation.tools.paste.disable = "FALSE"'
echo '   isolation.tools.setGUIOptions.enable = "TRUE"'
echo "3. Save the file and restart the VM"
echo -e "${YELLOW}================================================${NC}"
echo ""
notify-send "Clipboard fix applied. Reboot VM + edit .vmx on host." 2>/dev/null || true
