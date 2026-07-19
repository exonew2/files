# /etc/skel/.bashrc — Secure default shell for new users

# Default umask (prevent group/other write permissions)
umask 027

# History: don't record repeated commands, limit size, share
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

# Aliases
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ln='ln -i'
alias ll='ls -la'
alias la='ls -A'

# PATH safety — never include .
PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

# Editor
EDITOR=nano
VISUAL=nano

# Prompt
PS1='[\u@\h \W]\$ '
