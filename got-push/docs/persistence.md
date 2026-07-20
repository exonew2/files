# Persistence — What Survives Reboot

This project deploys scripts on an existing Arch Linux filesystem. There are no Btrfs subvolumes, no Snapper snapshots, and no special filesystem layout. Persistence is provided by your underlying filesystem.

## What Persists

| Path | Content | Persists Reboot |
|------|---------|-----------------|
| `/var/lib/qdrant/` | Qdrant vector database (collections, points, payloads) | ✅ |
| `~/.ollama/` | Ollama models (nomic-embed-text and any others) | ✅ |
| `~/.config/scripts/lsfs_launcher_hook.sh` | Bash launcher hook (Super+Space) | ✅ |
| `~/.config/scripts/lsfs_daemon.py` | Python LSFS indexing daemon | ✅ |
| `~/.config/systemd/user/lsfs-daemon.service` | User systemd unit for daemon | ✅ |
| `~/.config/hypr/` | Hyprland configuration | ✅ |
| `/etc/systemd/system/qdrant.service` | Qdrant systemd service | ✅ |

## What Does NOT Persist

- **Qdrant in-memory caches** — all indexed data is written to `/var/lib/qdrant/` on disk. No data is lost on clean shutdown.
- **Ollama model cache** — models stored in `~/.ollama/` persist. First-time `ollama pull` may be needed after wiping `~/.ollama`.

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

If the VM is lost or corrupted:

1. Deploy a fresh Arch Linux VM
2. Run the one-liner: `curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash`
3. Restore Qdrant data: `sudo tar -xzf qdrant-backup-*.tar.gz -C /`
4. Restore Ollama models: `tar -xzf ollama-backup-*.tar.gz -C ~`
5. Restore configs: `tar -xzf config-backup-*.tar.gz -C ~`
6. Restart services: `sudo systemctl restart qdrant && systemctl --user restart lsfs-daemon`
