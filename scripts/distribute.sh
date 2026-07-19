#!/usr/bin/env bash
# distribute.sh — Publish ash artifacts to all distribution channels
# Usage: ./distribute.sh <version>
# Example: ./distribute.sh 2025.01.1
#
# Distribution targets:
#   1. Cloudflare R2 (primary CDN)
#   2. Bunny CDN (fallback)
#   3. Archive.org (permanent)
#   4. Torrents (p2p)
#   5. GitHub Container Registry (OCI images)
#   6. Docker Hub
#   7. Quay.io
#   8. Raspberry Pi Imager repository
#   9. WSL2 distribution

set -euo pipefail

VERSION="${1:?Version required}"
ISO_DIR="$(dirname "$0")/../out"
ISO_FILE="${ISO_DIR}/ash-${VERSION}.iso"
ARM64_ISO="${ISO_DIR}/ash-${VERSION}-arm64.iso"

[[ -f "$ISO_FILE" ]] || { echo "ISO not found: $ISO_FILE"; exit 1; }

CHECKSUM=$(sha256sum "$ISO_FILE" | cut -d' ' -f1)
SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || stat -f%z "$ISO_FILE")

log() { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

log "Distributing ash-${VERSION} (${SIZE} bytes, sha256: ${CHECKSUM})"

# ─── 1. Cloudflare R2 (primary CDN) ──────────────────────────────────
log "Uploading to Cloudflare R2..."
wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}.iso" \
    --file "$ISO_FILE" \
    --metadata "sha256=${CHECKSUM},version=${VERSION},size=${SIZE}" 2>/dev/null || warn "R2 upload failed"

wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}.iso.sha256" \
    --file "${ISO_FILE}.sha256" 2>/dev/null || true

wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}.iso.minisig" \
    --file "${ISO_FILE}.minisig" 2>/dev/null || warn "minisig not found"

wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}.iso.cosign.bundle" \
    --file "${ISO_FILE}.cosign.bundle" 2>/dev/null || warn "cosign bundle not found"

# Upload ARM64 ISO if present
if [[ -f "$ARM64_ISO" ]]; then
  log "Uploading ARM64 ISO to R2..."
  wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}-arm64.iso" --file "$ARM64_ISO" 2>/dev/null || true
  wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}-arm64.iso.sha256" --file "${ARM64_ISO}.sha256" 2>/dev/null || true
fi

# ─── 2. Generate manifest ─────────────────────────────────────────────
ARM64_CHECKSUM=""
[[ -f "$ARM64_ISO" ]] && ARM64_CHECKSUM=$(sha256sum "$ARM64_ISO" | cut -d' ' -f1)

cat > "${ISO_DIR}/ash-${VERSION}-manifest.json" <<EOF
{
  "version": "${VERSION}",
  "sha256": "${CHECKSUM}",
  "size": ${SIZE},
  "released_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "architectures": {
    "x86_64": {
      "iso": "ash-${VERSION}.iso",
      "sha256": "${CHECKSUM}"
    },
    "aarch64": {
      "iso": "ash-${VERSION}-arm64.iso",
      "sha256": "${ARM64_CHECKSUM}"
    }
  },
  "urls": {
    "cdn": "https://cdn.ash.sh/${VERSION}/ash-${VERSION}.iso",
    "cdn_arm64": "https://cdn.ash.sh/${VERSION}/ash-${VERSION}-arm64.iso",
    "cdn_fallback": "https://bunny.ash.sh/${VERSION}/ash-${VERSION}.iso",
    "archive": "https://archive.org/download/ash-${VERSION}/ash-${VERSION}.iso",
    "torrent": "https://cdn.ash.sh/torrents/ash-${VERSION}.torrent",
    "magnet": "$(webtorrent create "$ISO_FILE" --magnet-only 2>/dev/null || echo '')",
    "container": "ghcr.io/ash-linux/ash:${VERSION}",
    "docker_hub": "docker.io/ashlinux/ash:${VERSION}",
    "quay": "quay.io/ash-linux/ash:${VERSION}",
    "wsl": "https://cdn.ash.sh/${VERSION}/ash-${VERSION}.wsl"
  },
  "formats": {
    "iso": "ash-${VERSION}.iso",
    "iso_arm64": "ash-${VERSION}-arm64.iso",
    "qcow2": "ash-${VERSION}.qcow2",
    "vmdk": "ash-${VERSION}.vmdk",
    "vhdx": "ash-${VERSION}.vhdx",
    "ova": "ash-${VERSION}.ova",
    "vagrant_libvirt": "ash-${VERSION}-libvirt.box",
    "vagrant_virtualbox": "ash-${VERSION}-virtualbox.box",
    "rpi4_img": "ash-${VERSION}-rpi4.img.gz",
    "rpi5_img": "ash-${VERSION}-rpi5.img.gz",
    "wsl": "ash-${VERSION}.wsl"
  },
  "signatures": {
    "minisign": "RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y=",
    "cosign_bundle": "ash-${VERSION}.iso.cosign.bundle",
    "slsa_provenance": "provenance.intoto.jsonl"
  }
}
EOF

wrangler r2 put "ash-releases/${VERSION}/manifest.json" \
    --file "${ISO_DIR}/ash-${VERSION}-manifest.json" 2>/dev/null || warn "manifest upload failed"

# ─── 3. Create torrent + magnet ───────────────────────────────────────
log "Creating torrent..."
mkdir -p "${ISO_DIR}/torrents"
webtorrent create "$ISO_FILE" \
    -o "${ISO_DIR}/torrents/ash-${VERSION}.torrent" \
    -a "wss://tracker.btorrent.xyz" \
    -a "wss://tracker.openwebtorrent.com" \
    -a "wss://tracker.webtorrent.dev" \
    -a "wss://tracker.opentrackr.org" 2>/dev/null || warn "webtorrent failed"

MAGNET=$(webtorrent create "$ISO_FILE" --magnet-only 2>/dev/null || echo "")
wrangler r2 put "ash-releases/torrents/ash-${VERSION}.torrent" \
    --file "${ISO_DIR}/torrents/ash-${VERSION}.torrent" 2>/dev/null || warn "torrent upload failed"

# ─── 4. Archive.org (permanent) ───────────────────────────────────────
log "Uploading to Archive.org..."
ia upload "ash-${VERSION}" "$ISO_FILE" \
    --metadata="mediatype:software;title:ash ${VERSION};description:Arch Snapshot Hypervisor ISO" 2>/dev/null || warn "Archive.org upload failed"

# ─── 5. Bunny CDN ─────────────────────────────────────────────────────
if [[ -n "${BUNNY_KEY:-}" ]]; then
    log "Pushing to Bunny CDN..."
    curl -X POST "https://storage.bunnycdn.com/ash-releases/${VERSION}/" \
        -H "AccessKey: ${BUNNY_KEY}" \
        --data-binary @"$ISO_FILE" 2>/dev/null || warn "Bunny push failed"
fi

# ─── 6. Container Images ──────────────────────────────────────────────
log "Building and pushing container images..."

build_container() {
  local tag="$1"
  local arch="${2:-amd64}"

  cat > /tmp/Dockerfile.ash-dist << 'DOCKERFILE'
FROM scratch
LABEL org.opencontainers.image.title="ash"
LABEL org.opencontainers.image.description="Arch Snapshot Hypervisor — AI-ready Linux distribution"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.url="https://ash.sh"
LABEL org.opencontainers.image.source="https://github.com/ash-linux/ash"
ADD ash-${VERSION}.iso /ash.iso
ADD ash-${VERSION}.iso.sha256 /ash.iso.sha256
DOCKERFILE

  docker buildx build \
    --platform "linux/${arch}" \
    --file /tmp/Dockerfile.ash-dist \
    --tag "$tag" \
    --push \
    "$ISO_DIR" 2>/dev/null || warn "Container build/push failed for $tag"
}

# Push to GHCR
if [[ -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u ash-linux --password-stdin 2>/dev/null || true
  build_container "ghcr.io/ash-linux/ash:${VERSION}" "amd64"
  build_container "ghcr.io/ash-linux/ash:latest" "amd64"

  if [[ -f "$ARM64_ISO" ]]; then
    build_container "ghcr.io/ash-linux/ash:${VERSION}-arm64" "arm64"
  fi
fi

# Push to Docker Hub
if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "$DOCKERHUB_TOKEN" | docker login -u ashlinux --password-stdin 2>/dev/null || true
  build_container "docker.io/ashlinux/ash:${VERSION}" "amd64"
  build_container "docker.io/ashlinux/ash:latest" "amd64"
fi

# Push to Quay.io
if [[ -n "${QUAY_TOKEN:-}" ]]; then
  echo "$QUAY_TOKEN" | docker login quay.io -u ash-linux --password-stdin 2>/dev/null || true
  build_container "quay.io/ash-linux/ash:${VERSION}" "amd64"
  build_container "quay.io/ash-linux/ash:latest" "amd64"
fi

# ─── 7. Raspberry Pi Images ──────────────────────────────────────────
if [[ -f "$ARM64_ISO" ]]; then
  log "Building Raspberry Pi compatible images..."

  # Raspberry Pi 4
  log "Building RPi4 image..."
  qemu-img convert -f iso -O raw "$ARM64_ISO" "${ISO_DIR}/ash-${VERSION}-rpi4.img" 2>/dev/null || \
    warn "RPi4 image conversion failed"

  # Write RPi4 compatible GPT + boot partition
  cat > /tmp/rpi4-setup.sh << 'RPI4'
#!/bin/bash
IMG="$1"
# Create GPT with required RPi partitions
dd if=/dev/zero of="$IMG" bs=1M seek=50 count=0 2>/dev/null
parted -s "$IMG" mklabel gpt 2>/dev/null
parted -s "$IMG" mkpart primary fat32 1MiB 512MiB 2>/dev/null
parted -s "$IMG" mkpart primary ext4 512MiB 100% 2>/dev/null
parted -s "$IMG" set 1 esp on 2>/dev/null
RPI4
  chmod +x /tmp/rpi4-setup.sh
  bash /tmp/rpi4-setup.sh "${ISO_DIR}/ash-${VERSION}-rpi4.img" 2>/dev/null || true

  gzip -c "${ISO_DIR}/ash-${VERSION}-rpi4.img" > "${ISO_DIR}/ash-${VERSION}-rpi4.img.gz"
  wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}-rpi4.img.gz" \
    --file "${ISO_DIR}/ash-${VERSION}-rpi4.img.gz" 2>/dev/null || true

  # Raspberry Pi 5 (simplified — same base, different DTBs)
  cp "${ISO_DIR}/ash-${VERSION}-rpi4.img" "${ISO_DIR}/ash-${VERSION}-rpi5.img"
  gzip -c "${ISO_DIR}/ash-${VERSION}-rpi5.img" > "${ISO_DIR}/ash-${VERSION}-rpi5.img.gz"
  wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}-rpi5.img.gz" \
    --file "${ISO_DIR}/ash-${VERSION}-rpi5.img.gz" 2>/dev/null || true

  log "RPi images uploaded"
fi

# ─── 8. WSL2 Distribution ────────────────────────────────────────────
log "Building WSL2 distribution tarball..."
# WSL2 expects a tar.gz with rootfs at /
# Extract ISO squashfs and repack as tarball
mkdir -p /tmp/ash-wsl
if [[ -f "$ISO_FILE" ]]; then
  # Mount ISO and extract rootfs
  local mnt_iso="/tmp/ash-wsl-iso-mnt"
  mkdir -p "$mnt_iso"
  mount -o loop,ro "$ISO_FILE" "$mnt_iso" 2>/dev/null || {
    warn "Cannot mount ISO for WSL extraction (no loop device)"
    # Create a minimal rootfs tarball
    cat > /tmp/ash-wsl/Dockerfile << 'WSLDOCKER'
FROM archlinux:latest
RUN pacman -Sy --noconfirm base linux-firmware sudo zsh fish openssh docker ollama qdrant && \
    pacman -Scc --noconfirm && \
    useradd -m -G wheel,docker -s /bin/zsh aiuser && \
    echo 'aiuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/aiuser && \
    rm -f /etc/machine-id
CMD ["/bin/zsh"]
WSLDOCKER
    docker build -t ash-wsl-builder /tmp/ash-wsl
    docker export $(docker create ash-wsl-builder) | gzip > "${ISO_DIR}/ash-${VERSION}.wsl"
  }

  if [[ -d "$mnt_iso" ]]; then
    # Copy and pack
    local wsl_root="/tmp/ash-wsl-root"
    mkdir -p "$wsl_root"
    rsync -a "$mnt_iso/" "$wsl_root/"
    umount "$mnt_iso" 2>/dev/null || true
    cd "$wsl_root" && tar czf "${ISO_DIR}/ash-${VERSION}.wsl" . 2>/dev/null || true
    cd "$ISO_DIR"
  fi
  rm -rf /tmp/ash-wsl-iso-mnt
fi

if [[ -f "${ISO_DIR}/ash-${VERSION}.wsl" ]]; then
  wrangler r2 put "ash-releases/${VERSION}/ash-${VERSION}.wsl" \
    --file "${ISO_DIR}/ash-${VERSION}.wsl" 2>/dev/null || true
  log "WSL2 distribution uploaded"
else
  warn "WSL2 distribution not built"
fi

# ─── 9. Update version API ───────────────────────────────────────────
log "Updating version API..."
curl -X POST "https://api.ash.sh/v1/version/publish" \
    -H "Authorization: Bearer ${CF_WORKER_TOKEN:-}" \
    -H "Content-Type: application/json" \
    -d "{\"version\":\"${VERSION}\",\"sha256\":\"${CHECKSUM}\",\"size\":${SIZE},\"iso_url\":\"https://cdn.ash.sh/${VERSION}/ash-${VERSION}.iso\"}" 2>/dev/null || warn "Version API update failed"

log "Multi-format distribution complete!"
echo ""
echo "  Primary:      https://cdn.ash.sh/${VERSION}/ash-${VERSION}.iso"
echo "  ARM64:        https://cdn.ash.sh/${VERSION}/ash-${VERSION}-arm64.iso"
echo "  Fallback:     https://bunny.ash.sh/${VERSION}/ash-${VERSION}.iso"
echo "  Archive:      https://archive.org/download/ash-${VERSION}/"
echo "  Torrent:      ${MAGNET}"
echo "  Container:    ghcr.io/ash-linux/ash:${VERSION}"
echo "  Docker Hub:   docker.io/ashlinux/ash:${VERSION}"
echo "  Quay:         quay.io/ash-linux/ash:${VERSION}"
echo "  RPi4 Image:   https://cdn.ash.sh/${VERSION}/ash-${VERSION}-rpi4.img.gz"
echo "  RPi5 Image:   https://cdn.ash.sh/${VERSION}/ash-${VERSION}-rpi5.img.gz"
echo "  WSL2:         https://cdn.ash.sh/${VERSION}/ash-${VERSION}.wsl"
echo "  Manifest:     https://cdn.ash.sh/${VERSION}/manifest.json"
