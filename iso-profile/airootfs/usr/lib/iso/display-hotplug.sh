#!/usr/bin/bash
# /usr/lib/iso/display-hotplug.sh
set -euo pipefail

DRIVER="$1"
DISPLAY="${DISPLAY:-:0}"
export DISPLAY
export XAUTHORITY="/run/user/1000/gdm/Xauthority"

sleep 0.5

OUTPUTS=$(DISPLAY="$DISPLAY" xrandr --query | grep " connected" | cut -d' ' -f1)

for OUT in $OUTPUTS; do
    DISPLAY="$DISPLAY" xrandr --output "$OUT" --auto
done

# HiDPI detection
DPI=$(DISPLAY="$DISPLAY" xrandr --query | grep -m1 ' connected' | sed -n 's/.* \([0-9]\+\)mm x \([0-9]\+\)mm .*/\1 \2/p')
if [[ -n "$DPI" ]]; then
    W_MM=$(echo "$DPI" | awk '{print $1}')
    H_MM=$(echo "$DPI" | awk '{print $2}')
    W_PX=$(DISPLAY="$DISPLAY" xrandr --query | grep -m1 ' connected' | sed -n 's/.* \([0-9]\+\)x\([0-9]\+\) .*/\1/p')
    H_PX=$(DISPLAY="$DISPLAY" xrandr --query | grep -m1 ' connected' | sed -n 's/.* \([0-9]\+\)x\([0-9]\+\) .*/\2/p')
    if [[ -n "$W_MM" && "$W_MM" -gt 0 && -n "$W_PX" ]]; then
        DPI_CALC=$(( (W_PX * 254) / W_MM ))
        if [[ $DPI_CALC -gt 192 ]]; then
            sudo -u aiuser DISPLAY="$DISPLAY" gsettings set org.gnome.desktop.interface scaling-factor 2
            sudo -u aiuser DISPLAY="$DISPLAY" gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
        fi
    fi
done

case "$DRIVER" in
    qxl|virgl) systemctl reload spice-vdagentd 2>/dev/null || true ;;
    vmware) systemctl reload vmtoolsd 2>/dev/null || true ;;
    vbox) systemctl reload vboxservice 2>/dev/null || true ;;
esac