#!/usr/bin/env bash
# sign-provenance.sh — Generate SLSA provenance and sign artifacts
# Usage: ./sign-provenance.sh <version>

set -euo pipefail

VERSION="${1:?Version required}"
ISO_DIR="$(dirname "$0")/../out"
ISO_FILE="${ISO_DIR}/ash-${VERSION}.iso"

[[ -f "$ISO_FILE" ]] || { echo "ISO not found: $ISO_FILE"; exit 1; }

log() { echo -e "\033[0;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# Generate SLSA provenance using slsa-github-generator
log "Generating SLSA Level 3 provenance..."
docker run --rm \
    -v "$ISO_DIR:/artifacts" \
    -v "$(pwd):/src" \
    -w /src \
    gcr.io/slsa-framework/slsa-github-generator/generic_slsa3:v1.10.0 \
    /builder \
    --artifact-path "/artifacts/ash-${VERSION}.iso" \
    --provenance-path "/artifacts/provenance.intoto.jsonl" \
    --source-uri "github.com/ash-linux/ash" \
    --source-tag "v${VERSION}" \
    --builder-id "https://github.com/ash-linux/ash/.github/workflows/build-iso.yml@refs/heads/main"

# Verify the generated provenance
log "Verifying generated SLSA provenance..."
docker run --rm \
    -v "$ISO_DIR:/artifacts" \
    gcr.io/slsa-framework/slsa-verifier:v2.6.0 \
    verify-artifact \
    "/artifacts/ash-${VERSION}.iso" \
    --provenance-path "/artifacts/provenance.intoto.jsonl" \
    --source-uri "github.com/ash-linux/ash" \
    --source-tag "v${VERSION}" \
    --builder-id "https://github.com/ash-linux/ash/.github/workflows/build-iso.yml@refs/heads/main" || \
    warn "SLSA verification of self-generated provenance failed"

# Sign with cosign (keyless) with multiple attenations
log "Signing with cosign (keyless)..."
cosign sign-blob \
    --yes \
    --bundle "${ISO_FILE}.cosign.bundle" \
    --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    --tlog-upload=true \
    "$ISO_FILE"

# Sign with cosign via GitHub Actions OIDC (also produce detached signature)
log "Signing with cosign (detached)..."
cosign sign-blob \
    --yes \
    --output-signature "${ISO_FILE}.cosign.sig" \
    --output-certificate "${ISO_FILE}.cosign.cert" \
    --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "$ISO_FILE"

# Sign with minisign
log "Signing with minisign..."
if [[ -f ~/.sign/minisign.key ]]; then
    minisign -Sm "$ISO_FILE" -s ~/.sign/minisign.key -x "${ISO_FILE}.minisig"
else
    warn "minisign key not found at ~/.sign/minisign.key"
fi

# Generate SHA256 (always)
log "Generating SHA256 checksum..."
sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"

# Generate GitHub attestation
log "Generating GitHub attestation..."
gh attest create "$ISO_FILE" \
    --repo ash-linux/ash \
    --workflow build-iso.yml \
    --tag "v${VERSION}" 2>/dev/null || warn "gh attest failed (needs gh auth)"

log "Provenance generation complete!"
echo ""
echo "  Provenance:        ${ISO_DIR}/provenance.intoto.jsonl"
echo "  Cosign bundle:     ${ISO_FILE}.cosign.bundle"
echo "  Cosign sig+ cert:  ${ISO_FILE}.cosign.sig + ${ISO_FILE}.cosign.cert"
echo "  Minisign:          ${ISO_FILE}.minisig"
echo "  SHA256:            ${ISO_FILE}.sha256"
echo ""
echo "  To verify all signatures run:"
echo "    cosign verify-blob --bundle ${ISO_FILE##*/}.cosign.bundle ${ISO_FILE##*/}"
echo "    slsa-verifier verify-artifact ${ISO_FILE##*/} --provenance-path provenance.intoto.jsonl --source-uri github.com/ash-linux/ash --source-tag v${VERSION}"
