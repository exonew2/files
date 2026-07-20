---
title: Quick Start
description: Deploy LSFS on an existing Arch Linux Hyprland VM with one curl command.
order: 1
---

## Prerequisites

- Arch Linux VMware VM (VMware Fusion on macOS / Workstation on Linux/Windows)
- Hyprland + Catppuccin Mocha theme
- Ollama installed with `ollama serve` available
- `sudo` access

## One-Liner Deploy

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

## What the Script Does (8 Phases)

1. **System prep** — dependencies, directories, permissions
2. **Qdrant install** — standalone binary + systemd service
3. **Ollama config** — ensures `nomic-embed-text` is pulled and pinned in VRAM
4. **LSFS daemon** — Python watcher that indexes files to Qdrant
5. **Launcher hook** — pure-bash script at `~/.config/scripts/lsfs_launcher_hook.sh` (curl to Ollama API + Qdrant API)
6. **VMware fixes** — VMX workaround for Hyprland display, clipboard config
7. **Auto-login** — enables automatic Hyprland session on boot
8. **Auto-start** — systemd services + wofi launcher on Super+Space

## Post-Deploy Usage

- Press **Super+Space** to open **wofi**
- Search by **concept** (e.g. "config") or **time** (e.g. "42h")
- The launcher hook queries Ollama embeddings → Qdrant → returns matching files

## Troubleshooting

```bash
# Re-run the deploy (idempotent)
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash

# Check individual services
systemctl status qdrant ollama lsfs-daemon

# Test embedding pipeline
curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"hello"}' | jq '.embedding | length'
```
