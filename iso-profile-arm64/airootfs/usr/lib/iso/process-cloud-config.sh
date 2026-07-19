#!/usr/bin/env bash
# /usr/lib/iso/process-cloud-config.sh — Parse and apply cloud-config YAML

set -euo pipefail

INPUT="${1:-/dev/stdin}"
TMP=$(mktemp)
cat "$INPUT" > "$TMP"

if command -v yq >/dev/null; then
    # SSH authorized keys
    yq -r '.ssh_authorized_keys[]?' "$TMP" 2>/dev/null | while read -r key; do
        mkdir -p /home/aiuser/.ssh
        echo "$key" >> /home/aiuser/.ssh/authorized_keys
    done
    chmod 700 /home/aiuser/.ssh 2>/dev/null || true
    chmod 600 /home/aiuser/.ssh/authorized_keys 2>/dev/null || true
    chown -R aiuser:aiuser /home/aiuser/.ssh 2>/dev/null || true

    # Git config
    GIT_NAME=$(yq -r '.git_config.name // ""' "$TMP")
    GIT_EMAIL=$(yq -r '.git_config.email // ""' "$TMP")
    [[ -n "$GIT_NAME" ]] && sudo -u aiuser git config --global user.name "$GIT_NAME"
    [[ -n "$GIT_EMAIL" ]] && sudo -u aiuser git config --global user.email "$GIT_EMAIL"

    # Write files (dotfiles, configs)
    yq -r '.write_files[]? | @base64' "$TMP" 2>/dev/null | while read -r encoded; do
        entry=$(echo "$encoded" | base64 -d)
        path=$(echo "$entry" | yq -r '.path')
        content=$(echo "$entry" | yq -r '.content')
        permissions=$(echo "$entry" | yq -r '.permissions // "0644"')
        owner=$(echo "$entry" | yq -r '.owner // "aiuser:aiuser"')
        mkdir -p "$(dirname "$path")"
        echo "$content" > "$path"
        chmod "$permissions" "$path"
        chown "$owner" "$path"
    done

    # Run commands
    yq -r '.runcmd[]? | @sh' "$TMP" 2>/dev/null | while read -r cmd; do
        eval "$cmd" || true
    done
fi

rm -f "$TMP"