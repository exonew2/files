#!/usr/bin/env bash
set -euo pipefail

REPO="exonew2/files"
BRANCH="main"
ISO_DIR="$HOME/ash-iso"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }

info "Ash Agentic Swarm Habitat — Bootstrap"

if ! command -v git &>/dev/null; then
    info "Installing git..."
    if command -v pacman &>/dev/null; then sudo pacman -S --noconfirm git
    elif command -v apt &>/dev/null; then sudo apt install -y git
    elif command -v brew &>/dev/null; then brew install git
    else echo "ERROR: Install git manually"; exit 1; fi
fi

if [ -d "$ISO_DIR" ]; then
    info "Updating existing installation..."
    cd "$ISO_DIR" && git pull
else
    info "Cloning ash-iso..."
    git clone --depth=1 "https://github.com/$REPO.git" "$ISO_DIR"
    cd "$ISO_DIR"
fi

chmod +x scripts/*.sh 2>/dev/null || true
chmod +x iso-profile/airootfs/usr/lib/iso/*.sh 2>/dev/null || true

ok "Ash ISO files ready at $ISO_DIR"

if [ -f /etc/arch-release ]; then
    info "Running LSFS setup..."
    bash iso-profile/airootfs/usr/lib/iso/lsfs-setup.sh 2>/dev/null || warn "lsfs-setup skipped"
    info "Running first-boot setup..."
    bash iso-profile/airootfs/usr/lib/iso/first-boot.sh 2>/dev/null || warn "first-boot skipped"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Ash Agentic Swarm Habitat Ready                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Super+Space  → LSFS semantic search"
echo "  Super+D      → App launcher"
echo "  lsfs-query   → CLI search"
echo "  cd $ISO_DIR  → Project root"
