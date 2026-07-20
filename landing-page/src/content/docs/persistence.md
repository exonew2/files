---
title: Data Persistence
description: What survives a VM reboot and how to back up / restore your data.
order: 4
---

## What Survives Reboot

| Data | Path | Persists |
|------|------|----------|
| Qdrant vector store | `/var/lib/qdrant` | Yes |
| Ollama models + VRAM pin | `~/.ollama` | Yes |
| LSFS launcher hook | `~/.config/scripts` | Yes |
| Hyprland config (Catppuccin) | `~/.config/hypr` | Yes |

Qdrant writes all vectors, payloads, and collection metadata to disk. Ollama keeps `nomic-embed-text` in `~/.ollama/models`. The launcher hook at `~/.config/scripts/lsfs_launcher_hook.sh` and Hyprland dotfiles are both under the home directory, which survives reboot.

## Backup

```bash
# Qdrant data
sudo tar -czf ~/qdrant-backup.tar.gz /var/lib/qdrant

# Ollama models
tar -czf ~/ollama-backup.tar.gz ~/.ollama

# Configs
tar -czf ~/configs-backup.tar.gz ~/.config/scripts ~/.config/hypr
```

## Restore

After a fresh deploy, restore your data:

```bash
sudo tar -xzf ~/qdrant-backup.tar.gz -C /
tar -xzf ~/ollama-backup.tar.gz -C ~/
tar -xzf ~/configs-backup.tar.gz -C ~/
sudo systemctl restart qdrant ollama lsfs-daemon
```

## Fresh Deploy + Restore Workflow

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
# then restore from backup
```

## VMware Snapshot

For instant rollback: VM → Snapshot → Take Snapshot
