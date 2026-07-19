# /etc/skel/.profile — Ash Desktop profile

umask 027

if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi

export EDITOR=nvim
export VISUAL=nvim
export BROWSER=firefox
export TERMINAL=kitty
export PATH

# Ash environment
export XDG_CURRENT_DESKTOP=ash
export XDG_SESSION_TYPE=wayland
