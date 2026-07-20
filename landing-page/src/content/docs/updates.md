---
title: Updates
description: Update the ash-iso VM deployment via git pull and service restarts.
order: 5
---

## Update Scripts and Config

The project is version-controlled. Update with:

```bash
cd /opt/ash-iso  # or wherever deployed
sudo git pull
```

Then re-run any applicable setup scripts or restart services:

```bash
sudo systemctl restart ollama qdrant
```

## Update Ollama Models

```bash
ollama pull nomic-embed-text
```

## Update Qdrant

Qdrant is installed as a standalone binary. To upgrade:

```bash
# Check current version
/usr/local/bin/qdrant --version

# Download newer binary
sudo curl -L "https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
  -o /tmp/qdrant.tar.gz
sudo tar xzf /tmp/qdrant.tar.gz -C /usr/local/bin/
sudo systemctl restart qdrant
```

## Rollback

The deployment scripts are idempotent. Re-run `ultimate-fix-v2.sh` to restore a known state:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```
