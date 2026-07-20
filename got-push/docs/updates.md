# Updates — Keeping ash-iso Current

## Manual Update

```bash
cd ~/ash-iso
git pull
bash scripts/ultimate-fix-v2.sh
```

The script is idempotent — it re-downloads Qdrant binary if newer, re-writes daemon files, and restarts services as needed.

## One-Liner Re-Run

Same as initial deploy:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

Safe to run any time. Does not destroy existing Qdrant data or Ollama models.

## Check Current Version

```bash
git log --oneline -1
```

The repo at `~/ash-iso` tracks the latest version. There are no version tags — the commit hash is the source of truth.

## Component Updates

### Ollama

```bash
# Update Ollama itself (Arch package)
sudo pacman -S ollama

# Update models
ollama pull nomic-embed-text
ollama list
```

### Qdrant

The `ultimate-fix-v2.sh` script fetches the latest Qdrant release from GitHub automatically. No manual step needed.

### LSFS Daemon + Launcher

Updated via `git pull && bash scripts/ultimate-fix-v2.sh`. Script re-writes `~/.config/scripts/lsfs_daemon.py` and `~/.config/scripts/lsfs_launcher_hook.sh`.

## System Updates

```bash
# Regular Arch system update
sudo pacman -Syu

# Re-run ash-iso deploy after system update if services break
bash ~/ash-iso/scripts/ultimate-fix-v2.sh
```
