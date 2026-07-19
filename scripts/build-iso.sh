#!/usr/bin/env bash
# build-iso.sh — Build ash ISO using mkarchiso
# Usage: ./build-iso.sh <version>
# Example: ./build-iso.sh 2025.01.1

set -euo pipefail

VERSION="${1:?Version required (e.g., 2025.01.1)}"
PROFILE_DIR="$(dirname "$0")/../iso-profile"
WORK_DIR="/tmp/ash-iso-build-${VERSION}"
OUT_DIR="$(dirname "$0")/../out"
ISO_NAME="ash-${VERSION}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

echo -e "${CYAN}"
cat <<'EOF'
  █████╗ ██████╗ ██████╗ ██╗██████╗ 
 ██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗
 ███████║██████╔╝██████╔╝██║██████╔╝
 ██╔══██║██═══╝ ██╔══██╗██║██╔═══╝ 
 ██║  ██║██║     ██║  ██║██║██║     
 ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝      
EOF
echo -e "${NC}"
echo -e "  Building ash ISO v${VERSION}"
echo ""

# Check root
[[ $EUID -eq 0 ]] || { err "Must run as root (mkarchiso requirement)"; exit 1; }

# Clean previous build
log "Cleaning previous build..."
rm -rf "${WORK_DIR}" "${OUT_DIR}/${ISO_NAME}.iso"

# Build
log "Running mkarchiso..."
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}" 2>&1 | tee "${OUT_DIR}/build-${VERSION}.log"

# Rename output
mv "${OUT_DIR}/ash-linux-*.iso" "${OUT_DIR}/${ISO_NAME}.iso" 2>/dev/null || true

# Generate checksums
log "Generating checksums..."
cd "${OUT_DIR}"
sha256sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.sha256"
sha256sum -c "${ISO_NAME}.iso.sha256"

# Sign with minisign
if [[ -f ~/.sign/minisign.key ]]; then
    log "Signing with minisign..."
    minisign -Sm "${ISO_NAME}.iso" -s ~/.sign/minisign.key -x "${ISO_NAME}.iso.minisig"
else
    warn "minisign key not found at ~/.sign/minisign.key — skipping minisign"
fi

# Sign with cosign (keyless)
if command -v cosign &>/dev/null; then
    log "Signing with cosign (keyless)..."
    cosign sign-blob --yes --bundle "${ISO_NAME}.iso.cosign.bundle" "${ISO_NAME}.iso" 2>/dev/null || warn "cosign failed"
else
    warn "cosign not installed — skipping cosign"
fi

# Verify build
log "Verifying ISO boots in QEMU..."
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 4G -smp 4 \
  -drive file="${OUT_DIR}/${ISO_NAME}.iso",media=cdrom,readonly=on \
  -boot d -display none -serial stdio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -watchdog i6300esb -no-reboot -daemonize -pidfile /tmp/qemu-ash.pid

# Wait for SSH
for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2222 aiuser@localhost "systemctl is-active graphical.target" 2>/dev/null | grep -q active; then
        log "✅ ISO boots successfully"
        break
    fi
    sleep 5
done
kill $(cat /tmp/qemu-ash.pid 2>/dev/null) 2>/dev/null || true

log "Build complete!"
echo ""
echo "  ISO: ${OUT_DIR}/${ISO_NAME}.iso"
echo "  SHA256: $(cat ${OUT_DIR}/${ISO_NAME}.iso.sha256 | cut -d' ' -f1)"
echo "  Size: $(du -h ${OUT_DIR}/${ISO_NAME}.iso | cut -f1)"
echo ""
echo "  Next steps:"
echo "    ./scripts/sign-provenance.sh ${VERSION}"
echo "    ./scripts/distribute.sh ${VERSION}"