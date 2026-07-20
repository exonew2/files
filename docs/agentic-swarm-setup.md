# Agentic Swarm — Desktop Integration

How the agentic desktop environment works on a deployed Arch Linux VMware VM: the window manager, launcher, notifications, clipboard, auto-login, and service orchestration.

## Overview

The deployed system bootstraps into a fully functional desktop with:

- **Hyprland** (Wayland compositor) as the display server
- **Wofi** as the application launcher and LSFS search UI
- **SwayNC** as the notification daemon
- **Waybar** as the status bar
- **Ollama** + **Qdrant** + **LSFS** running as background services
- **Auto-login** to Hyprland on boot — no login screen
- **VMware clipboard** integration for copy/paste between host and guest

## Desktop Environment

| Component | Role | Key Binding |
|-----------|------|-------------|
| **Hyprland** | Wayland compositor | — |
| **Wofi** | Application launcher + semantic search UI | Super+D (apps), Super+Space (LSFS search) |
| **SwayNC** | Notification center / notification daemon | — |
| **Waybar** | Status bar with workspaces, clock, system tray | — |

All components use the **Catppuccin Mocha** theme (dark purple/navy palette, pink accents).

### Hyprland config

Located at `~/.config/hypr/hyprland.conf`. Key bindings relevant to the agentic setup:

```conf
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
bind = SUPER, D, exec, wofi --show drun
exec-once = swaync
exec-once = waybar
```

## VMware Display

Wayland on VMware requires a display configuration workaround. Add these lines to the VM's `.vmx` file on the **host** machine:

```text
mks.enableVulkanRenderer = "FALSE"
svga.disableFIFO = "TRUE"
```

- `mks.enableVulkanRenderer = "FALSE"` — Disables VMware's Vulkan renderer, which causes tearing, black boxes, and freezes in Hyprland/Wayland. Falls back to the SVGA GPU.
- `svga.disableFIFO = "TRUE"` — Disables the SVGA FIFO to prevent rendering artifacts.

Inside the VM, no special display configuration is needed — Hyprland auto-detects the SVGA device.

## Clipboard

Clipboard sharing between the VMware host and the Arch VM requires two sides:

### Guest side (inside the VM)

`open-vm-tools` provides the clipboard integration:

```bash
# Services that must be running:
systemctl enable --now open-vm-tools.service    # vmtoolsd — main service
systemctl enable --now vmware-vmblock-fuse.service  # file system block driver
```

`vmware-user` runs as a user process and handles clipboard synchronization:

```bash
/usr/bin/vmware-user  # launched via Hyprland exec-once or xdg-autostart
```

### Host side (Windows/Linux/macOS)

The VM's `.vmx` file must explicitly enable clipboard operations:

```text
isolation.tools.copy.disable = "FALSE"
isolation.tools.paste.disable = "FALSE"
isolation.tools.setGUIOptions.enable = "TRUE"
```

Without these, VMware Workstation/Player blocks clipboard access by default for security.

### Testing
```bash
# On the guest, after vmtoolsd is running:
echo "test" | xclip -selection clipboard
# Paste on the host — should work if all three .vmx keys are set
```

Note: If clipboard stops working after a VM suspend/resume cycle, restart `open-vm-tools`:
```bash
sudo systemctl restart open-vm-tools
```

## Auto-login

The system boots straight to Hyprland without a login prompt. Two methods are supported:

### Method A: SDDM autologin
```ini
# /etc/sddm.conf.d/autologin.conf
[Autologin]
User=aiuser
Session=hyprland
```

### Method B: agetty autologin + .bash_profile
```bash
# /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin aiuser --noclear %I $TERM
```

The user's `~/.bash_profile` or `~/.bashrc` then execs Hyprland:

```bash
# ~/.bash_profile (last line)
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    exec Hyprland
fi
```

This avoids a display manager entirely, saving memory and boot time.

## Auto-start

All services start automatically on boot:

### System services

| Service | Purpose | Port | Status |
|---------|---------|------|--------|
| `ollama.service` | LLM server for embeddings | `127.0.0.1:11434` | `systemctl status ollama` |
| `qdrant.service` | Vector database | `127.0.0.1:6333` (TCP), `/tmp/lsfs.sock` (UDS) | `systemctl status qdrant` |
| `open-vm-tools.service` | VMware guest tools | — | `systemctl status open-vm-tools` |
| `vmware-vmblock-fuse.service` | VMware file system bridge | — | `systemctl status vmware-vmblock-fuse` |

### User services

| Service | Purpose | Status command |
|---------|---------|---------------|
| `lsfs-daemon.service` | File watcher + indexer | `systemctl --user status lsfs-daemon` |
| `lsfs-parity.timer` | Daily orphan cleanup | `systemctl --user status lsfs-parity.timer` |
| `lsfs-parity.service` | Oneshot parity check | `systemctl --user status lsfs-parity` |

User services are enabled at boot via `loginctl enable-linger`:

```bash
loginctl enable-linger aiuser
```

### Startup order

1. `qdrant.service` starts (depends on `network.target`)
2. `ollama.service` starts (depends on `network.target`)
3. `lsfs-daemon.service` starts (depends on both, declared via `After` and `Wants`)
4. `lsfs-daemon.service` runs an `ExecStartPost` warmup query to prime the Ollama model cache
5. `lsfs-parity.timer` fires daily, randomized within a 1-hour window
6. Hyprland auto-starts after agetty/SDDM session login
7. Hyprland `exec-once` starts `swaync`, `waybar`, `vmware-user`, and binds Super+Space

## Services Summary

| Service | Type | Port(s) | Resource limits | Logs |
|---------|------|---------|-----------------|------|
| `ollama.service` | System | `11434` | GPU pinned | `journalctl -u ollama -f` |
| `qdrant.service` | System | `6333` TCP, `6334` gRPC, `/tmp/lsfs.sock` UDS | `CPUQuota=50%`, `IOWeight=100` | `journalctl -u qdrant -f` |
| `open-vm-tools.service` | System | — | — | `journalctl -u open-vm-tools -f` |
| `vmware-vmblock-fuse.service` | System | — | — | `journalctl -u vmware-vmblock-fuse -f` |
| `lsfs-daemon.service` | User | — | `Nice=19`, `CPUQuota=30%`, `IOSchedulingClass=idle` | `journalctl --user -u lsfs-daemon -f` |
| `lsfs-parity.timer` | User | — | `Nice=19`, `IOSchedulingClass=idle` | `journalctl --user -u lsfs-parity -f` |

## Troubleshooting

### Hyprland won't start (black screen after boot)
- Check `~/.local/share/hyprland/hyprland.log` for GPU errors
- Ensure `.vmx` has `mks.enableVulkanRenderer = "FALSE"` and `svga.disableFIFO = "TRUE"`
- Boot with `LIBGL_ALWAYS_SOFTWARE=true` in the kernel command line or terminal

### Clipboard not working between host and guest
```
sudo systemctl restart open-vm-tools
sudo systemctl restart vmware-vmblock-fuse
```
Then verify `.vmx` contains all three `isolation.tools.*` keys set to `"FALSE"` (the keys are named `.disable`, but `"FALSE"` means "do not disable" — i.e., enable the feature).

### Wofi shows empty list on Super+Space
- Check that `lsfs_launcher_hook.sh` exists at `~/.config/scripts/` and is executable
- Test manually: `~/.config/scripts/lsfs_launcher_hook.sh`
- Check `notify-send` — if notifications appear, the hook is running
- Verify Qdrant and Ollama: `curl http://localhost:6333/health` and `curl http://localhost:11434/api/tags`
- The hook uses `--exec-search` flag which prevents empty-list freezes on VMware virtual GPU

### LSFS daemon not indexing
```
systemctl --user status lsfs-daemon          # check if running
journalctl --user -u lsfs-daemon -n 50       # recent logs
curl http://localhost:6333/collections/apps   # check collection exists
```
If the collection is missing, restart the daemon: `systemctl --user restart lsfs-daemon`

### Qdrant won't start
```
sudo systemctl status qdrant
journalctl -u qdrant -n 30
```
Common issues:
- Port `6333` already in use → `sudo lsof -i :6333`
- Storage directory permissions → `ls -la ~/.local/share/qdrant/`
- Socket file conflict → `sudo rm -f /tmp/lsfs.sock && sudo systemctl restart qdrant`

### Slow search results
- Confirm `nomic-embed-text` is loaded: `curl http://localhost:11434/api/tags | jq`
- Check Ollama is not swapping: `ollama ps`
- Verify Qdrant WAL is healthy: `curl -s http://localhost:6333/health`
- Run parity check: `lsfs-parity`
- Run a full re-index: `systemctl --user start lsfs-reindex`
