---
title: Updates
description: Update the deploy script, Qdrant binary, and Ollama model from the private repo.
order: 5
---

## Update Script and Config

The source lives at `github.com/exonew2/files` (private). Pull latest and re-run:

```bash
cd /path/to/files/repo
git pull
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

Re-running the script is idempotent — it re-applies all 8 phases without duplicating config.

## Qdrant Binary Upgrade

Qdrant runs as a standalone systemd service. To upgrade:

```bash
/usr/local/bin/qdrant --version  # check current
sudo curl -L "https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
  -o /tmp/qdrant.tar.gz
sudo tar xzf /tmp/qdrant.tar.gz -C /usr/local/bin/
sudo systemctl restart qdrant
```

## Ollama Model Update

Pull the latest `nomic-embed-text` (pinned in VRAM after deploy):

```bash
ollama pull nomic-embed-text
```

## Restart All Services

```bash
sudo systemctl restart qdrant ollama lsfs-daemon
```

## Rollback

Re-run the deploy script to restore a known good state:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```
