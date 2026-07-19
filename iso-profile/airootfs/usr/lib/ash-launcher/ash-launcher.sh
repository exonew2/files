#!/usr/bin/env bash
# /usr/lib/ash-launcher/ash-launcher.sh
# AI-powered application launcher for wofi
# Bind to Super+Shift+Space (AI launcher)
set -euo pipefail

LAUNCHER_PY="/usr/lib/ash-launcher/ash-launcher.py"

# Get AI-powered suggestions from launcher
SUGGESTIONS=$("$LAUNCHER_PY" --suggest "$@") || true

if [[ -z "$SUGGESTIONS" ]]; then
    notify-send -t 2000 "Ash Launcher" "No suggestions available — falling back to drun"
    SELECTED=$(wofi --dmenu --prompt "Launch app..." --cache-file /dev/null < /dev/null)
    [[ -z "${SELECTED:-}" ]] && exit 0
else
    SELECTED=$(echo "$SUGGESTIONS" | wofi --dmenu --prompt "AI Launch" --cache-file /dev/null) || exit 0
fi

[[ -z "${SELECTED:-}" ]] && exit 0

EXEC_CMD=$(echo "$SELECTED" | sed 's/^.*  |  //' | xargs)

# Extract app name for tracking
APP_NAME=$(echo "$EXEC_CMD" | awk '{print $1}' | xargs basename)

# Launch via Hyprland
hyprctl dispatch exec "$EXEC_CMD"

# Record launch in background
"$LAUNCHER_PY" --record "$APP_NAME" &
