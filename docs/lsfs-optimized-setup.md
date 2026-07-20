# LSFS — Linux Semantic Filesystem

A local semantic search engine for files on Arch Linux. Indexes files into a vector database and lets you search by meaning — not just filename.

## Overview

LSFS watches `~/.config/scripts` (and configurable paths), generates embeddings via Ollama, and stores them in Qdrant. Press **Super+Space** anywhere in Hyprland to open a semantic search prompt. Everything runs locally — no cloud, no API keys.

## Architecture

```
Hyprland (Super+Space)
    │
    ▼
wofi (dmenu prompt)
    │
    ▼
lsfs_launcher_hook.sh  (pure bash, ~50 lines)
    │
    ├──►  Ollama API (curl POST /api/embeddings)
    │         model: nomic-embed-text (768-dim)
    │
    └──►  Qdrant API (curl POST /collections/apps/points/search)
    │
    ▼
wofi (results list) → user selects → hyprctl dispatch exec
```

Write path (daemon):
```
inotify (file change)
    │
    ▼
lsfs_daemon.py (Python)
    │
    ├──►  Ollama API → embedding vector
    │
    └──►  Qdrant API → upsert point to "apps" collection
```

## The Launcher Hook

`~/.config/scripts/lsfs_launcher_hook.sh` is a pure-bash script (~50 lines, `curl` only). Bound to Super+Space:

1. Opens **wofi** with a query prompt
2. Sends query text to **Ollama** via `curl` to get a 768-dim embedding vector
3. Sends that vector to **Qdrant** via `curl` to search the `apps` collection
4. Displays results in **wofi** for selection
5. Opens the selected path via `hyprctl dispatch exec`:
   - Directories → `kitty -e yazi`
   - `.desktop` files → `gtk-launch`
   - Everything else → `kitty -e nvim`

**Time query support**: If the query matches patterns like "files from 42h" or "past 3 days", the hook falls back to `fd`/`find` with `-mtime` filters instead of vector search.

**Notification feedback**: `notify-send` displays stages — "Querying vectors...", "Searching: <query>", "Results ready".

## The Daemon

`~/.config/scripts/lsfs_daemon.py` is a Python background process that:

- **Watches the filesystem** with `pyinotify` for `IN_CLOSE_WRITE`, `IN_MOVED_TO`, `IN_DELETE` events
- **Debounces writes** — waits for file content to stabilize before processing
- **Generates embeddings** via Ollama's `/api/embeddings` endpoint using `nomic-embed-text`
- **Upserts points** into Qdrant's `apps` collection with payload: `path`, `name`, `chunk`, `chunk_text`, `ext`, `model`, `mtime`
- **Filters out** binary files and ignored paths based on `~/.lsfsignore`
- **Falls back to 60s polling** if `pyinotify` is unavailable

**Dependencies**: `pyinotify`, `python-magic` — installed via `pip install --user`.

## Qdrant Integration

Qdrant runs as a **standalone binary** downloaded from GitHub releases — no AUR dependency. Managed by a systemd service:

- **Collection**: `apps` with 768-dim vectors and Cosine distance
- **Storage**: `/var/lib/qdrant/`
- **Port**: `localhost:6333`

### Health check
```bash
curl -s http://localhost:6333/health
curl -s http://localhost:6333/collections/apps
```

## Embedding Model

**nomic-embed-text** — 768-dim Ollama-native embedding model:

- **Ollama-native** — no separate Python ML stack, no PyTorch
- **No query/passage prefixes needed** — raw text works directly
- **Fast inference** — runs comfortably on CPU

Pulled on first deploy:
```bash
ollama pull nomic-embed-text
ollama run nomic-embed-text  # warm up + pin in VRAM
```

## Deployment

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

The script runs in phases:

| Phase | What it does |
|-------|-------------|
| 1 | System tuning: inotify limits, swappiness, sysctl |
| 2 | Package installation: `wofi`, `jq` via pacman |
| 3 | Qdrant download: standalone binary from GitHub, storage dir, systemd service |
| 4 | Ollama: enables system service, pulls `nomic-embed-text`, pins with `keep_alive=-1` |
| 5 | LSFS scripts: writes `lsfs_launcher_hook.sh`, `lsfs_daemon.py` to `~/.config/scripts/` |
| 6 | systemd user services: installs `lsfs-daemon.service` in `~/.config/systemd/user/` |
| 7 | Writes `~/.lsfsignore`, installs Python dependencies via pip |
| 8 | Enables and starts all services, patches Hyprland config with Super+Space binding |

## Key Design Decisions

### Pure bash launcher hook (no Python)
The Super+Space → Search pipeline uses zero Python. The launcher hook calls Ollama and Qdrant APIs directly via `curl`. The script is ~50 lines and has one dependency: `curl`.

### Why nomic-embed-text?
- No query/passage prefixes needed — raw text works directly
- 768-dim, Ollama-native, fast on CPU
- 13M+ pulls, well-tested

### Why standalone Qdrant?
- No AUR dependency — binary download works on any Arch system
- Self-contained — no Docker, no Python SDK
- Simple systemd service

## File Reference

| File | Purpose |
|------|---------|
| `~/.config/scripts/lsfs_launcher_hook.sh` | Pure-bash launcher hook for Super+Space |
| `~/.config/scripts/lsfs_daemon.py` | Python daemon — watches files, indexes into Qdrant |
| `~/.config/systemd/user/lsfs-daemon.service` | systemd user service for the daemon |
| `~/.lsfsignore` | Ignore rules (gitignore-compatible) |

### Monitoring
```bash
journalctl --user -u lsfs-daemon -f   # daemon logs
curl -s http://localhost:6333/health  # Qdrant health
```
