# Quick Start — Deploy on Existing Arch Linux

## Prerequisites

- Arch Linux VM with Hyprland, git, and sudo access
- Ollama installed and running (`ollama serve` or `systemctl start ollama`)
- Internet connection for first-time setup

## One-Liner Deploy

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

Idempotent — safe to re-run. Installs:

- Qdrant standalone binary from GitHub releases → systemd service on `:6333`
- LSFS daemon (`~/.config/scripts/lsfs_daemon.py`) → user systemd service
- Launcher hook (`~/.config/scripts/lsfs_launcher_hook.sh`) → Super+Space
- VMware clipboard fix (`open-vm-tools` integration)
- Enables auto-login to Hyprland

## Post-Deploy

1. Reboot or restart Hyprland (Super+Shift+Q)
2. Press **Super+Space** to open the semantic launcher
3. Type a natural-language query (e.g. `my notes`, `config files`, `python scripts`)
4. Select a result → opens in Kitty + Neovim (or respective application)

## What to Test

- **Search by concept** — type "TODO lists" or "shell scripts" → returns semantically similar files
- **Search by time** — type "files from 42h" or "files from 3d" → falls back to `fd`/`find` time-based search
- **Tail daemon logs** — `journalctl --user -u lsfs-daemon -f` to see real-time indexing

## Troubleshooting

```bash
# Qdrant not responding
sudo systemctl status qdrant
sudo journalctl -u qdrant --no-pager -n 20

# Ollama not responding
systemctl status ollama
journalctl -u ollama --no-pager -n 20

# LSFS daemon not running
systemctl --user status lsfs-daemon
journalctl --user -u lsfs-daemon --no-pager -n 20

# Launcher hook missing
ls -l ~/.config/scripts/lsfs_launcher_hook.sh

# Re-run deploy (idempotent)
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

If the launcher reports "Ollama not running" or "Qdrant not running", verify the respective services and restart them.
