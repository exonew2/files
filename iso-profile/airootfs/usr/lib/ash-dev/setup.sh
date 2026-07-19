#!/usr/bin/bash
# /usr/lib/ash-dev/setup.sh — Initialize ash-dev developer environment
set -euo pipefail

log() { logger -t ash-dev "$*"; }
log "Setting up ash-dev developer environment"

# 1. Create user config directory
USER_HOME="/home/aiuser"
ASH_DIR="${USER_HOME}/.ash"
mkdir -p "${ASH_DIR}"/{dotfiles,scripts}
chown -R aiuser:aiuser "${ASH_DIR}"

# 2. Write default config templates
cat > "${ASH_DIR}/packages.toml" <<'EOF'
# Declarative package list for ash-conf
# Uncomment to add packages on next `ash-conf apply`

# [packages]
# add = ["htop", "btop", "neofetch"]
EOF
chown aiuser:aiuser "${ASH_DIR}/packages.toml"

cat > "${ASH_DIR}/services.toml" <<'EOF'
# Declarative service configuration for ash-conf
# Format: service_name = "enable|disable"

# ollama = "enable"
# qdrant = "enable"
# sshd = "enable"
EOF
chown aiuser:aiuser "${ASH_DIR}/services.toml"

# 3. Ensure tools are executable
chmod +x /usr/bin/ash-new /usr/bin/ash-conf /usr/bin/ash-doctor /usr/bin/ash-version /usr/bin/ash-tui 2>/dev/null || true

# 4. Ensure templates are accessible
chmod -R 755 /usr/share/ash-dev/templates/ 2>/dev/null || true
chmod +x /usr/share/ash-tui/ash-tui.py 2>/dev/null || true

# 5. Create user-local bin directory
mkdir -p "${USER_HOME}/.local/bin"

# 6. Add completion scripts if bash-completion exists
if [[ -d /usr/share/bash-completion/completions ]]; then
    for tool in ash-new ash-conf ash-doctor ash-version ash-tui; do
        ln -sf /dev/null "/usr/share/bash-completion/completions/${tool}" 2>/dev/null || true
    done
fi

log "ash-dev environment initialized"
