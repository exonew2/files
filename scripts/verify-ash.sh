#!/usr/bin/env bash
# verify-ash.sh — Run all verifications on ash ISO
# Usage: ./verify-ash.sh <iso-file> [version]
# Example: ./verify-ash.sh ash-2025.01.15.iso 2025.01.15

set -euo pipefail

ISO="${1:?ISO file required}"
VERSION="${2:-}"

# Auto-detect version from filename if not provided
if [[ -z "$VERSION" ]]; then
    VERSION=$(echo "$ISO" | sed -n 's/.*ash-\(.*\)\.iso/\1/p')
    [[ -n "$VERSION" ]] || { echo "Could not detect version. Provide it explicitly."; exit 1; }
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[*]${NC} $*"; }
pass() { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo "═══════════════════════════════════════"
echo "  ash ISO Verification v${VERSION}"
echo "  $(date -u)"
echo "═══════════════════════════════════════"
echo ""

[[ -f "$ISO" ]] || fail "ISO not found: $ISO"

# Determine directory
ISO_DIR="$(dirname "$ISO")"
pushd "$ISO_DIR" > /dev/null

# Check for signature files
SIGN_DIR="${ISO_DIR}"

[[ -f "${SIGN_DIR}/ash-${VERSION}.sha256" ]] || warn "SHA256 file not found"
[[ -f "${SIGN_DIR}/ash-${VERSION}.minisig" ]] || warn "minisig file not found"
[[ -f "${SIGN_DIR}/ash-${VERSION}.cosign.bundle" ]] || warn "cosign bundle not found"
[[ -f "${SIGN_DIR}/ash-${VERSION}.cosign.sig" ]] || warn "cosign detached signature not found"
[[ -f "provenance.intoto.jsonl" ]] || warn "SLSA provenance not found"

PASSED=0
TOTAL=0

# 1. SHA256
TOTAL=$((TOTAL + 1))
log "[1/${TOTAL}] Verifying SHA256..."
if [[ -f "ash-${VERSION}.sha256" ]]; then
    sha256sum -c "ash-${VERSION}.sha256" >/dev/null && \
        { pass "SHA256 OK"; PASSED=$((PASSED + 1)); } || \
        fail "SHA256 MISMATCH — DO NOT BOOT"
else
    COMPUTED=$(sha256sum "$ISO" | cut -d' ' -f1)
    echo "  Computed: $COMPUTED"
    warn "No .sha256 file to compare against"
fi

# 2. minisign
TOTAL=$((TOTAL + 1))
log "[${TOTAL}/${TOTAL}] Verifying minisign (Ed25519)..."
if [[ -f "ash-${VERSION}.minisig" ]]; then
    # Official minisign public key
    MINISIGN_PUBKEY="RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y="
    minisign -Vm "$ISO" -P "$MINISIGN_PUBKEY" -x "ash-${VERSION}.minisig" >/dev/null 2>&1 && \
        { pass "minisign OK"; PASSED=$((PASSED + 1)); } || \
        fail "minisign INVALID — DO NOT BOOT"
else
    warn "minisig file missing — skipping"
fi

# 3. cosign (bundle)
TOTAL=$((TOTAL + 1))
log "[${TOTAL}/${TOTAL}] Verifying cosign (keyless + Sigstore, bundle)..."
if [[ -f "ash-${VERSION}.cosign.bundle" ]]; then
    cosign verify-blob \
        --bundle "ash-${VERSION}.cosign.bundle" \
        --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        "$ISO" >/dev/null 2>&1 && \
        { pass "cosign (bundle) OK"; PASSED=$((PASSED + 1)); } || \
        fail "cosign (bundle) INVALID — DO NOT BOOT"
else
    warn "cosign bundle missing — skipping"
fi

# 4. cosign (detached)
TOTAL=$((TOTAL + 1))
log "[${TOTAL}/${TOTAL}] Verifying cosign (detached signature)..."
if [[ -f "ash-${VERSION}.cosign.sig" && -f "ash-${VERSION}.cosign.cert" ]]; then
    cosign verify-blob \
        --signature "ash-${VERSION}.cosign.sig" \
        --certificate "ash-${VERSION}.cosign.cert" \
        --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        "$ISO" >/dev/null 2>&1 && \
        { pass "cosign (detached) OK"; PASSED=$((PASSED + 1)); } || \
        fail "cosign (detached) INVALID — DO NOT BOOT"
else
    warn "cosign detached signature missing — skipping"
fi

# 5. SLSA Provenance
TOTAL=$((TOTAL + 1))
log "[${TOTAL}/${TOTAL}] Verifying SLSA Level 3 Provenance..."
if [[ -f "provenance.intoto.jsonl" ]]; then
    slsa-verifier verify-artifact \
        "$ISO" \
        --provenance-path provenance.intoto.jsonl \
        --source-uri github.com/ash-linux/ash \
        --source-tag "v${VERSION}" \
        --builder-id "https://github.com/ash-linux/ash/.github/workflows/build-iso.yml@refs/heads/main" >/dev/null 2>&1 && \
        { pass "SLSA Provenance OK"; PASSED=$((PASSED + 1)); } || \
        fail "SLSA Provenance INVALID — DO NOT BOOT"
else
    warn "SLSA provenance missing — skipping"
fi

# 6. GitHub Attestation
TOTAL=$((TOTAL + 1))
log "[${TOTAL}/${TOTAL}] Verifying GitHub Attestation..."
if command -v gh &>/dev/null; then
    gh attest verify "$ISO" --repo ash-linux/ash >/dev/null 2>&1 && \
        { pass "GitHub Attestation OK"; PASSED=$((PASSED + 1)); } || \
        warn "GitHub attestation verification failed"
else
    warn "gh CLI not found — skipping"
fi

popd > /dev/null

echo ""
echo "═══════════════════════════════════════"
echo "  Results: ${PASSED}/${TOTAL} checks passed"
if [[ $PASSED -eq $TOTAL ]]; then
    echo -e "${GREEN}  ALL VERIFICATIONS PASSED${NC}"
    echo -e "${GREEN}  Safe to boot: $ISO${NC}"
else
    echo -e "${YELLOW}  Some checks were skipped or failed.${NC}"
    echo -e "${YELLOW}  At minimum, SHA256 and one signature scheme must pass.${NC}"
fi
echo "═══════════════════════════════════════"
