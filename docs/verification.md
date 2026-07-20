# Verification — Health Checks

## Quick Health Check Table

Run `bash scripts/ultimate-fix-v2.sh` — it prints this table at the end:

| Component | Check Command | Expected |
|-----------|---------------|----------|
| Qdrant | `curl http://localhost:6333/health` | JSON response, status up |
| Ollama | `curl http://localhost:11434/api/tags` | JSON with `nomic-embed-text` |
| LSFS Daemon | `systemctl --user is-active lsfs-daemon` | `active` |
| Launcher Hook | `test -x ~/.config/scripts/lsfs_launcher_hook.sh` | Executable file exists |

## Individual Checks

### Qdrant

```bash
curl http://localhost:6333/health
```

Expected: `{"status":"ok","version":"..."}` or similar health response.

```bash
# Verify the 'apps' collection exists
curl http://localhost:6333/collections/apps
```

### Ollama

```bash
# Check Ollama is running
curl http://localhost:11434/api/version

# Check nomic-embed-text model is available
curl http://localhost:11434/api/tags | grep nomic-embed-text

# If missing, pull it
ollama pull nomic-embed-text
```

### LSFS Daemon

```bash
systemctl --user status lsfs-daemon
```

Expected: `active (running)`. Check logs with:

```bash
journalctl --user -u lsfs-daemon -f
```

### Launcher Hook

```bash
# Verify file exists and is executable
ls -l ~/.config/scripts/lsfs_launcher_hook.sh

# Test manually (simulates Super+Space query)
bash ~/.config/scripts/lsfs_launcher_hook.sh
```

### End-to-End Test

```bash
# Embed a test string via Ollama
curl -X POST http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text","prompt":"test query"}'

# Search Qdrant
curl -X POST http://localhost:6333/collections/apps/points/search \
  -d '{"vector":[0.0, ... 768 zeros], "limit": 5, "with_payload": true}'
```

## Fix-All Script

```bash
bash /path/to/ash-iso/scripts/fix-all.sh
```

Diagnoses and restarts any failed service in the LSFS stack.
