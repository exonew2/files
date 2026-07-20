# Persistence

This project deploys scripts on an existing Arch Linux filesystem. There are no Btrfs subvolumes, no Snapper snapshots, and no special filesystem layout. Persistence is provided by your underlying filesystem.

## What Survives Reboot

| Path | Content | Persists |
|------|---------|----------|
| `/var/lib/qdrant/` | Qdrant vector database (collections, points, payloads) | ✅ |
| `~/.ollama/` | Ollama models (nomic-embed-text) | ✅ |
| `~/.config/scripts/lsfs_launcher_hook.sh` | Bash launcher hook (Super+Space) | ✅ |
| `~/.config/scripts/lsfs_daemon.py` | Python LSFS indexing daemon | ✅ |
| `~/.config/systemd/user/lsfs-daemon.service` | User systemd unit for daemon | ✅ |
| `~/.config/hypr/` | Hyprland configuration | ✅ |
| `/etc/systemd/system/qdrant.service` | Qdrant systemd service | ✅ |

## Backup

```bash
# Qdrant vector data
sudo tar -czf qdrant-backup-$(date +%F).tar.gz /var/lib/qdrant

# Ollama models
tar -czf ollama-backup-$(date +%F).tar.gz ~/.ollama

# Configuration
tar -czf config-backup-$(date +%F).tar.gz \
  ~/.config/scripts \
  ~/.config/systemd/user/lsfs-daemon.service \
  ~/.config/hypr
```

## Disaster Recovery

1. Deploy a fresh Arch Linux VM
2. Run the one-liner: `curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash`
3. Restore Qdrant data: `sudo tar -xzf qdrant-backup-*.tar.gz -C /`
4. Restore Ollama models: `tar -xzf ollama-backup-*.tar.gz -C ~`
5. Restore configs: `tar -xzf config-backup-*.tar.gz -C ~`
6. Restart services: `sudo systemctl restart qdrant && systemctl --user restart lsfs-daemon`
