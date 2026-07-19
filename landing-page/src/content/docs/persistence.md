---
title: Data Persistence
description: How data, models, and vector memory persist across reboots in ash using Btrfs subvolumes and Snapper snapshots.
order: 4
---

## Btrfs Subvolume Layout

```
/ (subvolume @)
├── /home (subvolume @home)          ← Your code, configs, models
├── /var/log (subvolume @log)        ← System logs
├── /var/cache (subvolume @cache)    ← Package cache
├── /var/lib/qdrant (subvolume @qdrant)  ← Vector DB (excluded from snapshots)
└── /.snapshots (subvolume @snapshots)   ← Snapper snapshots
```

## What Persists Across Reboots

| Path | Survives Reboot | Survives Snapshot Rollback |
|------|-----------------|---------------------------|
| `/home/aiuser/*` | Yes | No |
| `/var/lib/qdrant/*` | Yes | Yes (excluded from snapshots) |

## Snapshot Management

```bash
# List snapshots
snapper list

# Create manual snapshot
sudo snapper create --description "Before risky AI experiment"

# Rollback to snapshot #42
sudo snapper rollback 42
```

## Qdrant Persistence

Qdrant data in `/var/lib/qdrant` is excluded from Snapper snapshots, so vector memories survive rollbacks.

## Model Persistence

Ollama models stored in `~/.ollama/models` (persists in @home). Models pulled at runtime survive reboots.

## Backup Strategy

```bash
ssh aiuser@localhost -p 2222 "sudo snapper create --description 'Pre-backup' && tar -czf - /home/aiuser /var/lib/qdrant" > ash-backup.tar.gz
```

## Disaster Recovery

1. **Rollback failed experiment**: `snapper rollback <num>`
2. **Corrupted system**: Boot ISO → rollback from GRUB-Btrfs menu
3. **Complete VM loss**: Re-import ISO → 45s to desktop → restore `/home`
