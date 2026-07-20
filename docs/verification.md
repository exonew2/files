# Health Checks

## Quick Check Table

| Component | Check Command | Expected |
|-----------|---------------|----------|
| Qdrant | `curl http://localhost:6333/health` | JSON response, status ok |
| Ollama | `curl http://localhost:11434/api/tags` | JSON with `nomic-embed-text` |
| LSFS Daemon | `systemctl --user is-active lsfs-daemon` | `active` |
| Launcher Hook | `test -x ~/.config/scripts/lsfs_launcher_hook.sh` | Exit code 0 |

## Individual Checks

### Qdrant
```bash
curl http://localhost:6333/health
```
Expected: `{"status":"ok","version":"..."}`

```bash
curl http://localhost:6333/collections/apps
```

### Ollama
```bash
curl http://localhost:11434/api/version
curl http://localhost:11434/api/tags | grep nomic-embed-text
```

If missing: `ollama pull nomic-embed-text`

### LSFS Daemon
```bash
systemctl --user status lsfs-daemon
```
Expected: `active (running)`. Logs: `journalctl --user -u lsfs-daemon -f`

### Launcher Hook
```bash
ls -l ~/.config/scripts/lsfs_launcher_hook.sh
bash ~/.config/scripts/lsfs_launcher_hook.sh
```

## Fix-All

Re-run the deploy script — it is idempotent and restarts all services:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```
