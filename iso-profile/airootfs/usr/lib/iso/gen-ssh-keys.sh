#!/usr/bin/bash
# /usr/lib/iso/gen-ssh-keys.sh — Generate SSH host keys on first boot
set -euo pipefail

log() { logger -t iso-ssh-keys "$*"; }

KEY_DIR="/etc/ssh"
KEY_TYPES=("ed25519" "rsa")

# Skip if keys already exist
for key in "${KEY_TYPES[@]}"; do
    if [[ -f "${KEY_DIR}/ssh_host_${key}_key" ]]; then
        log "SSH host key ${key} already exists, skipping generation"
        exit 0
    fi
done

log "Generating SSH host keys..."

# Regenerate all host keys
rm -f "${KEY_DIR}/ssh_host_"*
ssh-keygen -A 2>&1 | logger -t iso-ssh-keys

# Set proper permissions
chmod 600 "${KEY_DIR}/ssh_host_"*_key
chmod 644 "${KEY_DIR}/ssh_host_"*_key.pub

log "SSH host keys generated successfully"

# Generate user SSH key for aiuser if not present
USER_SSH_DIR="/home/aiuser/.ssh"
if [[ ! -f "${USER_SSH_DIR}/id_ed25519" ]]; then
    mkdir -p "$USER_SSH_DIR"
    ssh-keygen -t ed25519 -f "${USER_SSH_DIR}/id_ed25519" -N "" -C "aiuser@ash-iso" 2>&1 | logger -t iso-ssh-keys
    cat "${USER_SSH_DIR}/id_ed25519.pub" >> "${USER_SSH_DIR}/authorized_keys"
    chmod 700 "$USER_SSH_DIR"
    chmod 600 "${USER_SSH_DIR}/id_ed25519"
    chmod 644 "${USER_SSH_DIR}/id_ed25519.pub"
    chmod 600 "${USER_SSH_DIR}/authorized_keys"
    chown -R aiuser:aiuser "$USER_SSH_DIR"
    log "User SSH key generated for aiuser"
fi
