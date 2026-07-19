# /etc/profile.d/lsfs-integration.sh
# LSFS shell integration — aliases, functions, and completions

# Source shared completions
if [ -f /usr/share/ash-shell/lsfs-completions ]; then
    . /usr/share/ash-shell/lsfs-completions
fi
