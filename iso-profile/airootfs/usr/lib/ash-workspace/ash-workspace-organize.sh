#!/usr/bin/env bash
# /usr/lib/ash-workspace/ash-workspace-organize.sh
# Trigger: Super+Shift+A → auto-organize windows by category
set -euo pipefail

notify-send -t 2000 "Ash Workspace" "Organizing windows..."

python3 << 'PYEOF'
import dbus, json, sys
try:
    bus = dbus.SessionBus()
    workspace = bus.get_object('org.ash.Workspace', '/org/ash/Workspace')
    iface = dbus.Interface(workspace, 'org.ash.Workspace')
    result = json.loads(iface.Organize())
    if result.get("status") == "organized":
        moved = result.get("moved", 0)
        layout = result.get("layout", {})
        layout_str = ", ".join(f"WS{k}: {v}" for k, v in layout.items())
        print(f"Moved {moved} windows | {layout_str}")
    else:
        print(f"Organize result: {result}")
except dbus.exceptions.DBusException as e:
    print(f"Workspace Manager not running. Start with:\n  systemctl --user start ash-workspace.service\n\nError: {e}")
except Exception as e:
    print(f"Error: {e}")
PYEOF

notify-send -t 3000 "Ash Workspace" "Windows organized!"
