---
title: System Updates
description: Update ash ISO, pacman packages, Ollama models, and manage Btrfs snapshot rollbacks after updates.
order: 5
---

## Philosophy

- **You own the environment** — it's Arch, not an immutable container
- **Kernel held** — `linux`, `linux-headers`, `linux-firmware` pinned via `IgnorePkg`
- **Weekly auto-update** — creates pre/post snapshots, runs `pacman -Syu`

## Manual Update

```bash
# Full system update (kernel held)
sudo pacman -Syu

# Include kernel
sudo pacman -Syu linux linux-headers linux-firmware
```

## Auto-Update (Weekly)

Enabled by default via `iso-auto-update.timer`:

```bash
# Check status
systemctl list-timers iso-auto-update.timer

# Run manually
sudo systemctl start iso-auto-update.service
```

## Snapshot Safety

Every auto-update creates a pre/post snapshot pair. If an update breaks something:

```bash
snapper list
sudo snapper rollback <num>
reboot
```

## Model Updates

```bash
ollama pull llama3.2
ollama pull codellama
ollama rm llama3.1:8b  # remove old
```

## Cleanup

```bash
sudo paccache -rk3                    # Clean package cache (keep 3 versions)
sudo journalctl --vacuum-time=2weeks  # Clean journal
```
