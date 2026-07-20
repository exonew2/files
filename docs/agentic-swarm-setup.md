# Desktop Integration — Hyprland + VMware

How the deployed Arch Linux VMware VM is configured: window manager, launcher, auto-login, services, and what still needs host-side action.

## Desktop Environment

| Component | Role | Key Binding |
|-----------|------|-------------|
| **Hyprland** | Wayland compositor | — |
| **Wofi** | Application launcher + semantic search UI | Super+D (apps), Super+Space (LSFS search) |

Catppuccin Mocha theme (dark purple/navy palette, pink accents).

### Hyprland Config

`~/.config/hypr/hyprland.conf`:

```conf
bind = SUPER, Space, exec, $HOME/.config/scripts/lsfs_launcher_hook.sh
bind = SUPER, D, exec, wofi --show drun
```

## VMware Display

Wayland on VMware requires a VMX workaround. Add to the VM's `.vmx` file on the **host** machine:

```
mks.enableVulkanRenderer = "FALSE"
svga.disableFIFO = "TRUE"
```

Without these, Hyprland may experience tearing, black boxes, or freezes. Reboot the VM after editing `.vmx`.

**Status**: Requires host-side action — edit `.vmx` on the Windows/macOS host.

## Clipboard

`open-vm-tools` is installed inside the VM. For clipboard to work, the host's `.vmx` file must also have:

```
isolation.tools.copy.disable = "FALSE"
isolation.tools.paste.disable = "FALSE"
isolation.tools.setGUIOptions.enable = "TRUE"
```

**Status**: Requires host-side action — edit `.vmx` on the Windows/macOS host. Without these keys, VMware blocks clipboard by default.

## Auto-Login

Configured via agetty + `.bash_profile`. No display manager.

`/etc/systemd/system/getty@tty1.service.d/autologin.conf`:
```
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin pal --noclear %I $TERM
```

`~/.bash_profile`:
```bash
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    exec Hyprland
fi
```

## Auto-Start

All services start automatically on boot:

| Service | Type | Port | Status Command |
|---------|------|------|----------------|
| `ollama.service` | System | `127.0.0.1:11434` | `systemctl status ollama` |
| `qdrant.service` | System | `127.0.0.1:6333` | `systemctl status qdrant` |
| `open-vm-tools.service` | System | — | `systemctl status open-vm-tools` |
| `lsfs-daemon.service` | User | — | `systemctl --user status lsfs-daemon` |

User services enabled via `loginctl enable-linger pal`.

### Startup Order

1. `qdrant.service` starts (depends on `network.target`)
2. `ollama.service` starts (depends on `network.target`)
3. `lsfs-daemon.service` starts (depends on both)
4. Hyprland auto-starts via agetty + `.bash_profile`
5. Hyprland binds Super+Space to the launcher hook

## Troubleshooting

### Hyprland won't start (black screen)
- Check `~/.local/share/hyprland/hyprland.log` for GPU errors
- Ensure `.vmx` has `mks.enableVulkanRenderer = "FALSE"` and `svga.disableFIFO = "TRUE"`

### Clipboard not working
- Verify `.vmx` contains all three `isolation.tools.*` keys set to `"FALSE"`
- Restart open-vm-tools: `sudo systemctl restart open-vm-tools`

### Wofi shows empty list on Super+Space
- Check `lsfs_launcher_hook.sh` exists at `~/.config/scripts/` and is executable
- Test manually: `~/.config/scripts/lsfs_launcher_hook.sh`
- Verify Qdrant and Ollama: `curl http://localhost:6333/health` and `curl http://localhost:11434/api/tags`

### LSFS daemon not indexing
```bash
systemctl --user status lsfs-daemon
journalctl --user -u lsfs-daemon -n 50
curl http://localhost:6333/collections/apps
```

### Qdrant won't start
```bash
sudo systemctl status qdrant
journalctl -u qdrant -n 30
```
Common: port 6333 in use (`sudo lsof -i :6333`), storage directory permissions.
