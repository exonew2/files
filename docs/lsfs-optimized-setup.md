# LSFS — Linux Semantic Filesystem

A local semantic search engine for files on Arch Linux. LSFS indexes your home directory into a vector database and lets you search by meaning — not just filename.

## Overview

LSFS (Linux Semantic Filesystem) watches your filesystem, generates embeddings via a local LLM, and stores them in a vector database. Press **Super+Space** anywhere in Hyprland to open a semantic search prompt. Results are scored by relevance to your query's meaning.

Everything runs locally — no cloud, no API keys, no internet dependency after setup.

## Architecture

```
Hyprland (Super+Space)
    │
    ▼
wofi (dmenu prompt)
    │
    ▼
lsfs_launcher_hook.sh  (pure bash)
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

`~/.config/scripts/lsfs_launcher_hook.sh` is a pure-bash script (no Python dependencies). It is bound to Super+Space in Hyprland's config:

1. Opens **wofi** with a query prompt
2. Sends query text to **Ollama** via `curl` to get a 768-dim embedding vector
3. Sends that vector to **Qdrant** via `curl` to search the `apps` collection
4. Displays results in **wofi** as a second dmenu for selection
5. Opens the selected path via `hyprctl dispatch exec`:
   - Directories → `kitty -e yazi`
   - `.desktop` files → `gtk-launch`
   - Everything else → `kitty -e nvim`

**Time query support**: If the query matches patterns like "files from 42h" or "past 3 days", the hook falls back to `fd`/`find` with `-mtime` filters instead of vector search. This avoids embedding timestamp-sensitive queries.

**Notification feedback**: `notify-send` displays stages — "Querying vectors...", "Searching: <query>", "Results ready" — with persistent notification IDs so they overwrite rather than stack.

## The Daemon

`~/.config/scripts/lsfs_daemon.py` is a Python background process that:

- **Watches the filesystem** with `pyinotify` for `IN_CLOSE_WRITE`, `IN_MOVED_TO`, and `IN_DELETE` events
- **Debounces writes** — waits for file content to stabilize (3 consecutive identical hashes at 1.6s intervals) before processing
- **Generates embeddings** via Ollama's `/api/embeddings` endpoint using `nomic-embed-text`
- **Upserts points** into Qdrant's `apps` collection with payload: `path`, `name`, `chunk`, `chunk_text`, `ext`, `model`, `mtime`
- **Chunks code** using tree-sitter parsers (Python, JavaScript, TypeScript, Rust) with hierarchical scope metadata (`File > Class > Method`). Falls back to Python `ast` module when tree-sitter is unavailable. Large files (>500 lines) get signature+docstring summaries instead of full body.
- **Filters out** binary files, minified code, and ignored paths based on `~/.lsfsignore` (gitignore-compatible patterns)
- **Includes** tree-sitter and `ast`-based code chunking for struct/function/class extraction
- **Watches git HEAD** changes — detects branch switches and triggers automatic re-index of the affected repository
- **Runs at `nice(19)`** with `IOSchedulingClass=idle` to stay out of the way
- **Garbage collects** every 1000 files to prevent memory leaks; uses `asyncio` + `aiohttp` for non-blocking Ollama calls
- **Runs a daily parity timer** (`lsfs-parity.service`) that scrolls all points and removes orphans for deleted files
- **Falls back to 60s polling** if `pyinotify` is unavailable

**Dependencies**: `pyinotify`, `PyMuPDF`, `python-magic`, `tree-sitter` (optional), `aiohttp` — installed via `pip install --user`.

## Qdrant Integration

Qdrant runs as a **standalone binary** downloaded from GitHub releases — no AUR dependency. It is managed by a systemd service:

- **Collection**: `apps` with 768-dim vectors and Cosine distance
- **Storage**: `~/.local/share/qdrant/`
- **Socket**: `/tmp/lsfs.sock` (Unix domain socket) with TCP fallback on `localhost:6333`
- **gRPC port**: `6334`
- **Performance**: WAL mode, memory-mapped segments, 2 default segments, `memmap_threshold_kb=20000`, `indexing_threshold=10000`, `flush_interval_sec=5`
- **CPU quota**: `50%`, `IOWeight=100` — designed to not compete with Ollama for resources

On deployment, the service is overridden with a UDS config (`uds.conf`) and a CPU-only drop-in (`cpu-only.conf`).

### Health check
```bash
curl -s http://localhost:6333/health
curl -s http://localhost:6333/collections/apps
```

## Embedding Model

LSFS uses **nomic-embed-text** — a 768-dim Ollama-native embedding model:

- **Ollama-native** — no separate Python ML stack, no HuggingFace transformers, no PyTorch. Ollama manages the model entirely.
- **No query/passage prefixes needed** — unlike E5 or Instructor models, `nomic-embed-text` does not require `"query: "` or `"passage: "` prefixes. Raw text works directly.
- **Multilingual-capable** — performs well across languages without retuning.
- **Fast inference** on consumer GPUs — runs comfortably on a VM with GPU passthrough.
- **Pinned in VRAM** — Ollama's `keep_alive=-1` prevents model unloading.

The model is pulled on first deploy:
```bash
ollama pull nomic-embed-text
ollama run nomic-embed-text  # warm up + pin in VRAM
```

## Deployment

The entire system is deployed via a single curl-to-bash command:

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

The deployment script (`scripts/ultimate-fix-v2.sh`) runs in 8 phases:

| Phase | What it does |
|-------|-------------|
| 1 | System tuning: inotify limits (`fs.inotify.max_user_watches=524288`), swappiness, sysctl |
| 2 | Package installation: `wofi`, `swaync`, `jq` via pacman |
| 3 | Qdrant download: fetches standalone binary from GitHub, creates storage dir, installs systemd service with UDS + CPU tuning |
| 4 | Ollama: enables system service, pulls `nomic-embed-text`, pins with `keep_alive=-1` |
| 5 | LSFS scripts: writes `lsfs_launcher_hook.sh`, `lsfs_daemon.py`, `lsfs_query.py`, `lsfs_parity_check.py` to `~/.config/scripts/` |
| 6 | systemd user services: installs `lsfs-daemon.service`, `lsfs-parity.service`, `lsfs-parity.timer`, `lsfs-reindex.service` in `~/.config/systemd/user/` |
| 7 | Writes `~/.lsfsignore`, installs Python dependencies via pip |
| 8 | Enables and starts all services, patches Hyprland config with Super+Space binding |

## Key Design Decisions

### Pure bash launcher hook (no Python)
The Super+Space → Search pipeline uses zero Python. The launcher hook calls Ollama and Qdrant APIs directly via `curl`. This means the search UI works even if:
- The Python daemon is restarting
- `pip` is broken
- A virtualenv is corrupted
- The system has no Python venv configured

The script is ~50 lines and has one dependency: `curl`.

### Why nomic-embed-text?

| Factor | nomic-embed-text | E5 / multilingual-e5 |
|--------|-----------------|----------------------|
| Prefixes | None required | Requires `"query: "` / `"passage: "` |
| Dimensions | 768 | 384 / 768 |
| Ollama-native | Yes | Yes |
| Speed | Very fast | Fast |
| Community | 13M+ pulls | Smaller |

No query/passage prefix logic needed in the launcher hook — just raw query text. This keeps the bash hook simple.

### Why standalone Qdrant?
- No AUR package dependency — binary download works on any Arch system
- Self-contained — no Python ML stack, no database server
- UDS support for low-latency local communication
- Simple systemd service with resource limits

### Why a Python daemon?
The filesystem watcher and indexer benefits from:
- `pyinotify` for event-driven file change detection
- `aiohttp` for concurrent async embedding API calls
- `tree-sitter` / `ast` for intelligent code chunking
- `PyMuPDF` for PDF text extraction

This runs as a background service and can fail/restart without affecting the launcher hook.

## File Reference

| File | Purpose |
|------|---------|
| `scripts/ultimate-fix-v2.sh` | Master deployment script (the one-liner target) |
| `scripts/ultimate-fix.sh` | Original deployment script (v1) |
| `scripts/instant-launcher.sh` | Legacy launcher, replaced by the hook |
| `~/.config/scripts/lsfs_launcher_hook.sh` | Pure-bash launcher hook for Super+Space |
| `~/.config/scripts/lsfs_daemon.py` | Python daemon — watches files, indexes into Qdrant |
| `~/.config/scripts/lsfs_query.py` | Python query engine — hybrid search + cross-encoder reranking |
| `~/.config/scripts/lsfs_parity_check.py` | Daily orphan cleanup script |
| `~/.config/systemd/user/lsfs-daemon.service` | systemd user service for the daemon |
| `~/.config/systemd/user/lsfs-parity.service` | systemd oneshot for parity check |
| `~/.config/systemd/user/lsfs-parity.timer` | Daily timer for parity check |
| `~/.config/systemd/user/lsfs-reindex.service` | systemd oneshot for full re-index |
| `~/.lsfsignore` | Ignore rules (gitignore-compatible) |

### Monitoring
```bash
journalctl --user -u lsfs-daemon -f   # daemon logs
journalctl --user -u lsfs-parity      # parity check logs
curl -s http://localhost:6333/health  # Qdrant health
lsfs-query --list-mode "find this"    # test search
lsfs-parity                            # run parity check manually
```
