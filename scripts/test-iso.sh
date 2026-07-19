#!/usr/bin/env bash
# test-iso.sh — Comprehensive ISO test suite
# Usage: ./test-iso.sh <iso-path>

set -euo pipefail

ISO="${1:?ISO path required}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "${RED}✗ FAIL${NC}: $1"; exit 1; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "═══════════════════════════════════════"
echo " ash ISO Test Suite"
echo "═══════════════════════════════════════"

# Test 1: File exists and is ISO
[[ -f "$ISO" ]] && pass "ISO file exists" || fail "ISO file not found"
file "$ISO" | grep -q "ISO 9660" && pass "Valid ISO 9660" || fail "Not a valid ISO"

# Test 2: SHA256 matches
SHA256_FILE="${ISO}.sha256"
[[ -f "$SHA256_FILE" ]] && pass "SHA256 file exists" || fail "SHA256 file missing"
sha256sum -c "$SHA256_FILE" >/dev/null 2>&1 && pass "SHA256 matches" || fail "SHA256 mismatch"

# Test 3: minisign signature
MINISIG_FILE="${ISO}.minisig"
[[ -f "$MINISIG_FILE" ]] && pass "minisig file exists" || warn "minisig file missing (optional)"
if [[ -f "$MINISIG_FILE" ]]; then
    minisign -Vm "$ISO" -P RWQf6LRCGA9i52mlZT2k5B5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y5Q5Y= -x "$MINISIG_FILE" >/dev/null 2>&1 && \
        pass "minisign signature valid" || fail "minisign signature invalid"
fi

# Test 4: cosign signature
COSIGN_BUNDLE="${ISO}.cosign.bundle"
[[ -f "$COSIGN_BUNDLE" ]] && pass "cosign bundle exists" || warn "cosign bundle missing (optional)"
if [[ -f "$COSIGN_BUNDLE" ]]; then
    cosign verify-blob \
        --bundle "$COSIGN_BUNDLE" \
        --certificate-identity-regexp "https://github.com/ash-linux/ash/.github/workflows/release.yml@refs/tags/v*" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        "$ISO" >/dev/null 2>&1 && pass "cosign signature valid" || fail "cosign signature invalid"
fi

# Test 5: Boot in QEMU (headless)
log "Testing ISO boot in QEMU..."
qemu-system-x86_64 \
    -enable-kvm -cpu host -m 4G -smp 4 \
    -drive file="$ISO",media=cdrom,readonly=on \
    -boot d -display none -serial stdio \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -watchdog i6300esb -no-reboot -daemonize -pidfile /tmp/qemu-test.pid

# Wait for graphical.target
for i in {1..90}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -p 2222 aiuser@localhost "systemctl is-active graphical.target" 2>/dev/null | grep -q active; then
        pass "Graphical target active"
        break
    fi
    sleep 5
done

# Test 6: AI user exists
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "id aiuser" 2>/dev/null | grep -q "uid=1000(aiuser)" && \
    pass "aiuser exists (UID 1000)" || fail "aiuser missing or wrong UID"

# Test 7: Passwordless sudo
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "sudo -n true" 2>/dev/null && \
    pass "Passwordless sudo works" || fail "sudo requires password"

# Test 8: SSH key-only auth
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config" 2>/dev/null && \
    pass "SSH key-only auth configured" || fail "SSH password auth enabled"

# Test 9: Ollama running
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "systemctl is-active ollama" 2>/dev/null | grep -q active && \
    pass "Ollama service active" || fail "Ollama not running"

# Test 10: phi3:mini model present (baked in ISO)
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "ollama list 2>/dev/null | grep -q phi3:mini" 2>/dev/null && \
    pass "phi3:mini model present" || warn "phi3:mini not found (may pull on first run)"

# Test 11: Qdrant running
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "systemctl is-active qdrant" 2>/dev/null | grep -q active && \
    pass "Qdrant service active" || fail "Qdrant not running"

# Test 12: Qdrant API responds
curl -sf http://localhost:6333/collections 2>/dev/null | grep -q "collections" && \
    pass "Qdrant API responds" || fail "Qdrant API not accessible"

# Test 13: Btrfs + Snapper
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "findmnt -n -o FSTYPE / | grep -q btrfs" 2>/dev/null && \
    pass "Root filesystem is Btrfs" || fail "Root not Btrfs"

ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "snapper list 2>/dev/null | head -5" 2>/dev/null && \
    pass "Snapper configured" || fail "Snapper not working"

# Test 14: Firewall active
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "systemctl is-active firewalld" 2>/dev/null | grep -q active && \
    pass "Firewall active" || fail "Firewall not running"

# Test 15: Guest agents
for agent in vmtoolsd vboxservice qemu-guest-agent spice-vdagent; do
    ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "systemctl is-active $agent" 2>/dev/null | grep -q active && \
        pass "$agent active" || warn "$agent not active (may not be on this hypervisor)"
done

# Test 16: Timezone/keyboard auto-detect (best effort)
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "localectl status" 2>/dev/null && \
    pass "localectl configured" || warn "localectl not set"

# Test 17: Persistence (home on separate subvolume)
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "findmnt -n -o SOURCE /home | grep -q '@home'" 2>/dev/null && \
    pass "Home on separate Btrfs subvolume" || warn "Home not on separate subvolume"

# Test 18: Qdrant excluded from snapshots
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "snapper -c root get-config | grep -q 'EXCLUDE.*qdrant'" 2>/dev/null && \
    pass "Qdrant excluded from snapshots" || warn "Qdrant not excluded from snapshots"

# Test 19: Auto-update timer exists
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "systemctl list-timers --all | grep -q iso-auto-update" 2>/dev/null && \
    pass "Auto-update timer configured" || fail "Auto-update timer missing"

# Test 20: Uninstall script present
ssh -o StrictHostKeyChecking=no -p 2222 aiuser@localhost "[[ -f ~/Desktop/iso-uninstall.sh ]]" 2>/dev/null && \
    pass "Uninstall script on desktop" || fail "Uninstall script missing"

# Cleanup
kill $(cat /tmp/qemu-test.pid 2>/dev/null) 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════"
echo " All tests passed!"
echo "═══════════════════════════════════════"