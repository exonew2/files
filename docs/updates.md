# System Updates

## Philosophy

- **You own the environment** — it's Arch, not an immutable container
- **Kernel held** — `linux`, `linux-headers`, `linux-firmware` pinned via `IgnorePkg`
- **Weekly auto-update** — creates pre/post snapshots, runs `pacman -Syu`
- **AUR via paru** — pre-installed, configured for `--noconfirm`

## Manual Update

```bash
# Full system update (kernel held)
sudo pacman -Syu

# Include kernel (when you want it)
sudo pacman -Syu linux linux-headers linux-firmware

# AUR packages
paru -Syu

# Clean cache
sudo pacman -Sc
paru -Sc
```

## Auto-Update (Weekly)

Enabled by default via `iso-auto-update.timer`:

- Runs weekly with 4h random delay
- Creates pre-update snapshot (type: pre, cleanup: number)
- Runs `pacman -Syu --noconfirm`
- Creates post-update snapshot (type: post, linked to pre)

```bash
# Check status
systemctl list-timers iso-auto-update.timer

# Run manually
sudo systemctl start iso-auto-update.service

# View logs
journalctl -u iso-auto-update.service -f

# Disable
sudo systemctl disable --now iso-auto-update.timer
```

## Snapshot Safety

Every auto-update creates a snapshot pair:

```
# Pre-update
snapper create --type pre --description "Auto-update: 2025-01-15 03:42" --userdata "type=auto-update"

# Post-update (linked)
snapper create --type post --pre-number 42 --description "Auto-update: 2025-01-15 03:45"
```

If update breaks something:

```bash
# List to find pre-update snapshot
snapper list

# Rollback
sudo snapper rollback 42
reboot
```

## Model Updates

```bash
# Update all Ollama models
ollama pull llama3.2
ollama pull codellama
ollama pull qwen2.5-coder

# List installed
ollama list

# Remove old
ollama rm llama3.1:8b
```

## AI Tool Updates

```bash
# Continue extension (VS Code)
code --install-extension continue.continue

# Cody (Sourcegraph)
code --install-extension sourcegraph.cody-ai

# llama.cpp (rebuild for new features)
cd /tmp && git clone https://github.com/ggerganov/llama.cpp && cd llama.cpp && make -j$(nproc) && sudo cp llama-cli /usr/local/bin/
```

## Holding Packages

```bash
# Hold a package
sudo pacman -Syu --ignore=package-name

# Permanent hold (edit /etc/pacman.conf)
IgnorePkg = linux linux-headers linux-firmware package-name

# Unhold
# Remove from IgnorePkg line
```

## Cleanup

```bash
# Remove orphaned packages
sudo pacman -Rns $(pacman -Qtdq)

# Clean package cache (keep 3 versions)
sudo paccache -rk3

# Clean AUR build dirs
paru -Sc

# Clean journal
sudo journalctl --vacuum-time=2weeks
```

## Update Notifications

```bash
# Check for updates without applying
checkupdates
paru -Qu

# Pretty output
pacman -Qu --color=always | head -20
```