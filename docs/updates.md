# Updates

## Manual Update

The deploy script is the update mechanism. Re-run it to get the latest version of all components:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

Safe to run any time — idempotent. Does not destroy existing Qdrant data or Ollama models.

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
The deploy script fetches the latest Qdrant release from GitHub automatically. No manual step needed.

### LSFS Daemon + Launcher
Re-run the deploy script — it re-writes `~/.config/scripts/lsfs_daemon.py` and `~/.config/scripts/lsfs_launcher_hook.sh`.

## System Updates

```bash
# Regular Arch system update
sudo pacman -Syu

# Re-run deploy after system update if services break
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```
