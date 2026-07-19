# /etc/bash.bashrc — System-wide bashrc (for all interactive shells)
# Secure defaults

# Default umask for all users
umask 027

# Safe history
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

# Safe aliases
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ln='ln -i'

# Never include . in PATH
if [[ $PATH == *:* ]]; then
    PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
fi
