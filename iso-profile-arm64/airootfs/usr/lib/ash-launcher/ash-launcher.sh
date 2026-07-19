#!/usr/bin/env bash
# /usr/lib/ash-launcher/ash-launcher.sh
# AI-powered application launcher for wofi
# Bind to Super+Space (replaces LSFS launcher hook in Hyprland)
set -euo pipefail

WOFI_CACHE="/dev/null"
LAUNCHER_SCRIPT="/usr/lib/ash-launcher/ash-launcher.py"

# Present wofi with AI suggestions
SUGGESTIONS=$(python3 << 'PYEOF'
import sys, os, json

sys.path.insert(0, '/usr/lib/ash-launcher')
from ash_launcher import AshLauncher

launcher = AshLauncher()
suggestions = launcher.get_launcher_suggestions()

# Format for wofi: Name | Exec
for s in suggestions[:15]:
    name = s.get('name', s.get('app', '?'))
    source = s.get('source', '')
    icon = {'recent': '🕐', 'intent': '🤖', 'history': '📊', 'time_based': '⏰'}.get(source, '')
    print(f"{icon} {name}  |  {s['exec']}")
PYEOF
)

if [[ -z "$SUGGESTIONS" ]]; then
    # Fallback to regular wofi drun if no suggestions
    SELECTED=$(wofi --dmenu --prompt "Launch app..." --cache-file "$WOFI_CACHE" < /dev/null)
    [[ -z "${SELECTED:-}" ]] && exit 0
    SELECTED=$(echo "$SELECTED" | sed 's/.*| //' | xargs)
    if echo "$SELECTED" | grep -q '\.desktop$'; then
        hyprctl dispatch exec "gtk-launch '$(basename "$SELECTED")'"
    else
        hyprctl dispatch exec "$SELECTED"
    fi
    exit 0
fi

SELECTED=$(echo "$SUGGESTIONS" | wofi --dmenu --prompt "AI Launch" --cache-file "$WOFI_CACHE") || exit 0
[[ -z "${SELECTED:-}" ]] && exit 0

EXEC_CMD=$(echo "$SELECTED" | sed 's/.*| //' | xargs)
hyprctl dispatch exec "$EXEC_CMD"

# Record launch in background
python3 << PYEOF &
import sys, os, json
sys.path.insert(0, '/usr/lib/ash-launcher')
from ash_launcher import record_launch
app_name = os.path.basename("""$EXEC_CMD""".split()[0])
record_launch(app_name)
PYEOF
