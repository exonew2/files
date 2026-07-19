# /etc/skel/.bashrc — Ash Desktop shell configuration

umask 027

HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ln='ln -i'
alias ll='eza -la --icons'
alias la='eza -A --icons'
alias lt='eza -laT --icons'
alias cat='bat'
alias grep='rg'
alias find='fd'
alias top='btop'
alias vim='nvim'
alias vi='nvim'
alias ip='ip -c'
alias df='df -h'
alias du='du -h'

PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
EDITOR=nvim
VISUAL=nvim

if command -v starship &>/dev/null; then
    eval "$(starship init bash)"
elif command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
fi

PS1='[\u@\h \W]\$ '
