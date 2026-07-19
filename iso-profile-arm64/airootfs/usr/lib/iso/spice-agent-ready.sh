#!/usr/bin/bash
# /usr/lib/iso/spice-agent-ready.sh
systemctl --user restart spice-vdagentd 2>/dev/null || systemctl restart spice-vdagentd