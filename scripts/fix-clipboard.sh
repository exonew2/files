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

info "Installing spice-vdagent open-vm-tools..."
sudo pacman -S --needed --noconfirm spice-vdagent open-vm-tools 2>/dev/null || \
    warn "Package install had issues — try: sudo pacman -S spice-vdagent open-vm-tools"

info "Enabling spice-vdagentd.service..."
sudo systemctl enable --now spice-vdagentd.service 2>/dev/null && ok "spice-vdagentd started" || \
    warn "spice-vdagentd failed to start"

info "Enabling vmtoolsd.service..."
sudo systemctl enable --now vmtoolsd.service 2>/dev/null && ok "vmtoolsd started" || \
    warn "vmtoolsd failed to start"

info "Creating Hyprland exec.conf..."
mkdir -p "$HOME/.config/hypr"
cat > "$HOME/.config/hypr/exec.conf" << 'CONF'
exec-once = spice-vdagent
CONF
ok "exec.conf created"

info "Adding udev rule for VMware guest isolation..."
UDEV_RULE='SUBSYSTEM=="misc", KERNEL=="vmw_vmci", GROUP="vmware", MODE="0660"'
if [ ! -f /etc/udev/rules.d/99-vmware-guest-isolation.rules ]; then
    echo "$UDEV_RULE" | sudo tee /etc/udev/rules.d/99-vmware-guest-isolation.rules > /dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    ok "Udev rule added"
else
    ok "Udev rule already exists"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  VMware Clipboard Fix Applied                             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}HOST SIDE — Add these lines to your .vmx file:${NC}"
echo "  isolation.tools.copy.disable = \"FALSE\""
echo "  isolation.tools.paste.disable = \"FALSE\""
echo ""
echo "After editing .vmx, restart the VM for full clipboard support."
echo ""
echo "To source exec.conf in Hyprland, ensure your hyprland.conf has:"
echo "  source = ~/.config/hypr/exec.conf"
echo "Then run: hyprctl reload"
