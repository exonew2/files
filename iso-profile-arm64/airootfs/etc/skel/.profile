# /etc/skel/.profile — Default profile for new users

umask 027

if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi

export EDITOR=nano
export VISUAL=nano
export PATH
