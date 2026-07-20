---
title: Health Checks
description: Verify Qdrant, Ollama, LSFS daemon, and the launcher hook are all running correctly.
order: 2
---

## Qdrant (standalone binary, systemd)

```bash
systemctl status qdrant
curl -s http://localhost:6333/healthz          # expect: OK
curl -s http://localhost:6333/collections      # list collections
```

## Ollama (nomic-embed-text, pinned in VRAM)

```bash
systemctl status ollama
curl -s http://localhost:11434/api/tags | jq   # expect nomic-embed-text:latest

# Generate a 768-dim embedding
curl -s http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"hello"}' | jq '.embedding | length'
# Expected: 768
```

## LSFS Daemon (Python file watcher)

```bash
systemctl status lsfs-daemon
journalctl -u lsfs-daemon --no-pager | tail -20
```

## Launcher Hook (pure-bash)

```bash
# The hook file exists
ls -la ~/.config/scripts/lsfs_launcher_hook.sh

# Run a semantic query via the hook
lsfs query "test query"
```

## Port Mappings

```bash
ss -tlnp | grep -E '11434|6333'
```

- `:11434` — Ollama
- `:6333` — Qdrant HTTP
- `:6334` — Qdrant gRPC

## Re-run Deploy to Fix

If anything is missing, the script is idempotent:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```
