#!/usr/bin/env bash
# build-all-formats.sh
set -euo pipefail

VERSION="${1:?Version required (e.g., 2025.01.1)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

log() { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

log "Building ash-${VERSION} — all formats"

# 1. Build ISO
log "Step 1/6: Building ISO..."
"$SCRIPT_DIR/build-iso.sh" "$VERSION"

ISO_FILE="$ROOT_DIR/out/ash-${VERSION}.iso"
[[ -f "$ISO_FILE" ]] || { echo "ISO not found: $ISO_FILE"; exit 1; }

# 2. Sign provenance
log "Step 2/6: Generating SLSA provenance & signatures..."
"$SCRIPT_DIR/sign-provenance.sh" "$VERSION"

# 3. Build VM formats via Packer
log "Step 3/6: Building VM formats..."
cd "$ROOT_DIR/packer"
packer init .
packer build -var "version=$VERSION" -var "iso_path=$ISO_FILE" ash-iso.pkr.hcl

# 4. Build cloud images
log "Step 4/6: Building cloud images..."
for cloud in aws-ami gcp-image azure-image; do
    [[ -f "$cloud.pkr.hcl" ]] && packer build -var "version=$VERSION" -var "iso_path=$ISO_FILE" "$cloud.pkr.hcl" || warn "$cloud skipped"
done

# 5. Build Vagrant box
log "Step 5/6: Building Vagrant box..."
[[ -f vagrant-box.pkr.hcl ]] && packer build -var "version=$VERSION" -var "iso_path=$ISO_FILE" vagrant-box.pkr.hcl || warn "Vagrant skipped"

# 6. Distribute
log "Step 6/6: Distributing..."
"$SCRIPT_DIR/distribute.sh" "$VERSION"

log "All formats built and distributed!"
echo ""
echo "Artifacts in out/:"
ls -lh "$ROOT_DIR/out/ash-${VERSION}"* 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'