# /etc/profile.d/ash-shell.sh
# Source Ash Shell integration for all users
# Provides AI-powered context hints when changing directories

if [ -f /usr/share/ash-shell/ash-shell-init.sh ]; then
    source /usr/share/ash-shell/ash-shell-init.sh
fi
