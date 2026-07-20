---
title: Data Persistence
description: How data, models, and vector store contents persist across VM reboots.
order: 4
---

## What Persists

| Data | Location | Survives Reboot |
|------|----------|-----------------|
| Ollama models | `~/.ollama/models` | Yes |
| Qdrant data | `/var/lib/qdrant` | Yes |
| LSFS config | `~/.config/lsfs` | Yes |
| System config | `/etc` | Yes |
| User home | `/home/*` | Yes |

Qdrant uses the `storage` directory defined in its config — all vectors, payloads, and collection metadata are written to disk and survive VM restarts.

## Backup

```bash
# Backup Qdrant data
tar -czf qdrant-backup.tar.gz /var/lib/qdrant

# Backup Ollama models
tar -czf ollama-models-backup.tar.gz ~/.ollama/models
```

## Restore

If the VM is rebuilt via the one-liner script, restore data after the first boot:

```bash
tar -xzf qdrant-backup.tar.gz -C /
tar -xzf ollama-models-backup.tar.gz -C ~/
systemctl restart qdrant ollama
```

## Snapshot via VMware

For instant rollback, take a VMware snapshot before making changes:

- VM → Snapshot → Take Snapshot
- Restore via: VM → Snapshot → Go to
