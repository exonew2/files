#!/usr/bin/env bash
# cross-build-arm64.sh — Build ARM64 (aarch64) ash ISO using cross-compilation
# Usage: ./cross-build-arm64.sh <version>
# Example: ./cross-build-arm64.sh 2025.01.1
#
# Methods (auto-detected, in priority order):
#   1. Docker buildx with multi-arch QEMU (preferred)
#   2. mkarchiso with qemu-user-static binfmt translation
#   3. Native ARM64 build (Apple Silicon / ARM server)

set -euo pipefail

VERSION="${1:-$(date +%Y.%m.%d)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
PROFILE_DIR="$ROOT_DIR/iso-profile-arm64"
OUT_DIR="$ROOT_DIR/out"
ISO_NAME="ash-${VERSION}-arm64"
WORK_DIR="/tmp/ash-arm64-build-${VERSION}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

arch_detect() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    aarch64|arm64) echo "native" ;;
    x86_64|amd64)  echo "cross" ;;
    *)             echo "unknown" ;;
  esac
}

# Ensure ARM64 profile exists
if [[ ! -d "$PROFILE_DIR" ]]; then
  err "ARM64 profile not found at $PROFILE_DIR"
  err "Run: mkdir -p $PROFILE_DIR && cp -r iso-profile/* iso-profile-arm64/"
  exit 1
fi

MODE=$(arch_detect)
log "Detected build mode: $MODE"
log "Building ash ARM64 v${VERSION}"

mkdir -p "$OUT_DIR"
rm -rf "$WORK_DIR"

case "$MODE" in
  native)
    log "Native ARM64 build — running mkarchiso directly"
    sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" 2>&1 | tee "$OUT_DIR/build-arm64-${VERSION}.log"
    ;;

  cross)
    log "Cross-architecture build — trying Docker buildx first"

    if command -v docker &>/dev/null && docker buildx version &>/dev/null; then
      log "Using Docker buildx with multi-arch QEMU"

      if ! docker buildx inspect ash-arm64-builder &>/dev/null; then
        docker run --privileged --rm tonistiigi/binfmt --install arm64
        docker buildx create --name ash-arm64-builder --driver docker-container --bootstrap
        docker buildx use ash-arm64-builder
      fi

      cat > /tmp/Dockerfile.ash-arm64 << 'DOCKERFILE'
FROM --platform=linux/arm64 archlinux:latest AS build
RUN pacman -Sy --noconfirm archiso mkinitcpio-archiso squashfs-tools btrfs-progs qemu-user-static-binfmt
COPY iso-profile-arm64 /iso-profile-arm64
RUN mkarchiso -v -w /tmp/build -o /out /iso-profile-arm64
DOCKERFILE

      docker buildx build \
        --platform linux/arm64 \
        --file /tmp/Dockerfile.ash-arm64 \
        --output "type=local,dest=$OUT_DIR" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        -t ash-arm64-builder:latest \
        "$ROOT_DIR" 2>&1 | tee "$OUT_DIR/build-arm64-${VERSION}.log"

      # Rename output if needed
      for f in "$OUT_DIR"/ash-linux-*.iso; do
        [[ -f "$f" ]] && mv "$f" "${f/ash-linux-*/ash-${VERSION}-arm64.iso}" 2>/dev/null || true
      done

    elif command -v mkarchiso &>/dev/null; then
      log "Using mkarchiso with qemu-user-static binfmt"
      if systemctl is-active systemd-binfmt &>/dev/null || ls /proc/sys/fs/binfmt_misc/qemu-aarch64 &>/dev/null 2>&1; then
        sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR" 2>&1 | tee "$OUT_DIR/build-arm64-${VERSION}.log"
      else
        err "qemu-user-static-binfmt not configured for aarch64"
        err "Run: sudo pacman -S qemu-user-static-binfmt && sudo systemctl restart systemd-binfmt"
        exit 1
      fi
    else
      err "No cross-build method available. Install Docker or archiso with QEMU binfmt."
      exit 1
    fi
    ;;

  *)
    err "Unknown architecture: $(uname -m)"
    exit 1
    ;;
esac

# Rename and checksum
if [[ -f "$OUT_DIR/${ISO_NAME}.iso" ]] || ls "$OUT_DIR"/ash-linux-*.iso &>/dev/null; then
  mv "$OUT_DIR"/ash-linux-*.iso "$OUT_DIR/${ISO_NAME}.iso" 2>/dev/null || true
  log "Signing ARM64 artifacts..."
  cd "$OUT_DIR"
  sha256sum "${ISO_NAME}.iso" > "${ISO_NAME}.iso.sha256"

  if [[ -f ~/.sign/minisign.key ]]; then
    minisign -Sm "${ISO_NAME}.iso" -s ~/.sign/minisign.key -x "${ISO_NAME}.iso.minisig"
  fi

  if command -v cosign &>/dev/null; then
    cosign sign-blob --yes --bundle "${ISO_NAME}.iso.cosign.bundle" "${ISO_NAME}.iso" 2>/dev/null || true
  fi

  log "ARM64 build complete!"
  echo ""
  echo "  ISO:    $OUT_DIR/${ISO_NAME}.iso"
  echo "  SHA256: $(cat ${ISO_NAME}.iso.sha256 | cut -d' ' -f1)"
  echo "  Size:   $(du -h ${ISO_NAME}.iso | cut -f1)"
else
  err "ARM64 ISO not produced. Check build log: $OUT_DIR/build-arm64-${VERSION}.log"
  exit 1
fi
