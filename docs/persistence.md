# Data Persistence

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
| `/home/aiuser/*` | ✅ | ❌ (reverts to snapshot) |
| `/var/lib/qdrant/*` | ✅ | ✅ (excluded from snapshots) |
| `/var/lib/ollama/*` | ✅ | ❌ (reverts) |
| `/etc/*` | ✅ | ❌ (reverts) |
| `/root/*` | ✅ | ❌ (reverts) |
| `/usr/*` | ✅ | ❌ (reverts) |

## Snapshot Management

```bash
# List snapshots
snapper list

# Create manual snapshot
sudo snapper create --description "Before risky AI experiment"

# Rollback to snapshot #42
sudo snapper rollback 42

# Delete old snapshots
sudo snapper delete 10-20

# GUI
snapper-gui
```

## Qdrant Persistence

Qdrant data lives in `/var/lib/qdrant` (subvolume `@qdrant`), which is **excluded from Snapper snapshots**. This means:

- Vector memories survive snapshot rollbacks
- AI remembers context across experiments
- Collections, points, and payloads persist

```bash
# Verify Qdrant excluded
snapper -c root get-config | grep EXCLUDE
# Should show: EXCLUDE_PATHS="/var/lib/qdrant"

# Backup Qdrant manually
tar -czf qdrant-backup-$(date +%F).tar.gz /var/lib/qdrant
```

## Model Persistence

Ollama models stored in `/usr/share/ollama/.ollama/models` (read-only in ISO) and `~/.ollama/models` (writable).

```bash
# Models pulled at runtime go to ~/.ollama (persists in @home)
ollama pull llama3.2

# To make models persistent across fresh ISO boots:
# 1. Pull models in running VM
# 2. Create snapshot: snapper create --description "Models pulled"
# 3. Rollback restores models instantly
```

## Backup Strategy

```bash
#!/usr/bin/env bash
# backup.sh — Run from host via SSH
VM="aiuser@localhost -p 2222"

ssh $VM "sudo snapper create --description 'Pre-backup snapshot'"
ssh $VM "tar -czf - /home/aiuser /var/lib/qdrant" > "ash-backup-$(date +%F).tar.gz"
ssh $VM "sudo snapper delete $(snapper list | grep 'Pre-backup' | awk '{print $1}')"
```

## Disaster Recovery

1. **Rollback failed experiment**: `snapper rollback <num>` → instant
2. **Corrupted system**: Boot ISO → `snapper rollback` from GRUB-Btrfs menu
3. **Lost Qdrant data**: Restore from `@qdrant` subvolume backup
4. **Complete VM loss**: Re-import ISO → 45s to desktop → restore `/home` from backup