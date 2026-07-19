#!/usr/bin/env bash
# waybar-ash-menu — System menu for Ash Waybar
set -euo pipefail

CHOICE=$(printf " Lock\n Logout\n鈴 Suspend\n敏 Hibernate\n Reboot\n Shutdown\n Ash Doctor\n Ash Config\n Check Updates" | wofi --dmenu -p "Ash Menu" -i -lines 9 -width 20 -location 1)

case "$CHOICE" in
    *Lock) swaylock ;;
    *Logout) hyprctl dispatch exit ;;
    *Suspend) systemctl suspend ;;
    *Hibernate) systemctl hibernate ;;
    *Reboot) systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
    *Doctor)
        kitty -e bash -c "
            echo '=== Ash Doctor ==='
            echo
            echo 'Ollama:'
            ollama list 2>/dev/null || echo '  not running'
            echo
            echo 'Qdrant:'
            curl -sf http://localhost:6333/health 2>/dev/null && echo '  healthy' || echo '  not running'
            echo
            echo 'LSFS:'
            mountpoint -q /mnt/lsfs 2>/dev/null && echo '  mounted' || echo '  not mounted'
            echo
            echo 'Memory:'
            free -h
            echo
            echo 'Disk:'
            df -h /
            echo
            read -p 'Press Enter to close'
        " ;;
    *Config)
        if command -v gnome-control-center &>/dev/null; then
            gnome-control-center
        elif [ -d "$HOME/.config/ash" ]; then
            kitty -e nvim "$HOME/.config/ash"
        fi
        ;;
    *Updates)
        kitty -e bash -c '
            echo "Checking for updates..."
            sudo pacman -Sy
            echo
            pacman -Qu 2>/dev/null || echo "System is up to date"
            echo
            read -p "Press Enter to close"
        ' ;;
esac
