# /etc/profile.d/lsfs-integration.sh
# LSFS shell integration — aliases, functions, and completions

case ":${PATH}:" in
    *:"${HOME}/.local/bin":*) ;;
    *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# Source shared completions
if [ -f /usr/share/ash-shell/lsfs-completions ]; then
    . /usr/share/ash-shell/lsfs-completions
fi
