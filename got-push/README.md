# Ash-ISO — Agentic Swarm Habitat OS

> Production-grade Arch Linux VM with semantic file search, vector memory, and an AI-native desktop launcher. Deploy on top of any Arch Linux install in one command.

## Quick Deploy

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

Idempotent. Safe to re-run. Installs everything below on an existing Arch Linux system.

## What You Get

| Feature | Description |
|---------|-------------|
| **Semantic Search** | Search files by concept using Ollama embeddings + Qdrant vector DB |
| **Super+Space Launcher** | woofi-based launcher hook — type a concept, get relevant files |
| **Vector Memory** | Qdrant standalone binary (no AUR, no Docker) persists embeddings across reboots |
| **LSFS Daemon** | Python-based indexing daemon that watches your project dirs and builds vector embeddings |
| **Hyprland Desktop** | Wayland compositor with auto-login, auto-start services, and VMware optimizations |
| **VMware Clipboard** | open-vm-tools with `vmware-user` integrated into Hyprland |
| **Auto-login** | Boots directly into Hyprland — no display manager, no login prompt |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Hyprland (Wayland Compositor)                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Super+Space → woofi (dmenu prompt)              │   │
│  │       │                                           │   │
│  │       ▼                                           │   │
│  │  lsfs_launcher_hook.sh (pure bash)                │   │
│  │       │                                           │   │
│  │       ├──→ POST /api/embeddings (Ollama)          │   │
│  │       │       nomic-embed-text → 768-dim vector   │   │
│  │       │                                           │   │
│  │       └──→ POST /collections/apps/points/search   │   │
│  │               Qdrant (localhost:6333)              │   │
│  │               │                                    │   │
│  │               ▼                                    │   │
│  │         Results piped back to woofi                │   │
│  │         Selection → hyprctl dispatch exec           │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Background Services:                                    │
│    ollama.service      → localhost:11434                 │
│    qdrant.service      → localhost:6333                  │
│    lsfs-daemon.service → Python indexer + FUSE mount     │
│    vmtoolsd.service    → VMware clipboard/sharing        │
└─────────────────────────────────────────────────────────┘
```

## Key Improvements

- **Pure-bash launcher** — The search hook (`scripts/instant-launcher.sh`) has zero Python dependencies at runtime. Calls Ollama and Qdrant APIs directly via `curl`. No `sentence-transformers`, no `fusepy`, no import overhead.
- **nomic-embed-text model** — 768-dimensional embeddings, Ollama-native. Small, fast, good-enough for semantic file search. Pulled automatically if missing.
- **Qdrant standalone binary** — Downloaded directly from `github.com/qdrant/qdrant/releases` as a static musl binary. Runs as a systemd service. No AUR, no Docker, no Python SDK needed.
- **VMware-first** — `.vmx` workaround (`mks.enableVulkanRenderer = "FALSE"`) eliminates Hyprland tearing/freezing. `open-vm-tools` for bidirectional clipboard.
- **Auto-start everything** — systemd services for Ollama, Qdrant, LSFS daemon, VMware tools all enabled at boot. Hyprland auto-login via `getty@tty1` override.
- **Graceful fallback** — If Qdrant is unreachable, the launcher falls back to `fd` / `find` for time-based or name-based file search.
- **Health check + auto-fix** — `scripts/fix-all.sh` runs a diagnostic on the full stack and restarts any dead service.

## Relevant Files

| File | Purpose |
|------|---------|
| `scripts/ultimate-fix-v2.sh` | One-shot deploy script — installs everything |
| `scripts/instant-launcher.sh` | Pure-bash search hook (Woofi → Ollama → Qdrant) |
| `scripts/fix-all.sh` | Health check + auto-restart for all services |
| `scripts/fix-clipboard.sh` | VMware clipboard repair |
| `scripts/deploy.sh` | Alternative deployment via repo clone |
| `iso-profile/airootfs/usr/lib/iso/lsfs-setup.sh` | First-boot LSFS setup |
| `iso-profile/airootfs/usr/lib/iso/qdrant-setup.sh` | First-boot Qdrant installation |
| `iso-profile/airootfs/usr/lib/ash-launcher/ash-launcher.sh` | Python-backed AI launcher (alternative) |

## Documentation

- [`docs/quickstart.md`](docs/quickstart.md) — Deploy on existing Arch Linux in one command
- [`docs/agentic-swarm-setup.md`](docs/agentic-swarm-setup.md) — Desktop integration guide (Hyprland, VMware, auto-login, services)
- [`docs/lsfs-optimized-setup.md`](docs/lsfs-optimized-setup.md) — LSFS semantic filesystem architecture and design
- [`docs/persistence.md`](docs/persistence.md) — What data survives reboot and how to back it up
- [`docs/gpu-passthrough.md`](docs/gpu-passthrough.md) — VMware GPU configuration and VMX workarounds
- [`docs/verification.md`](docs/verification.md) — Health checks for Qdrant, Ollama, daemon, and launcher
- [`docs/comparison.md`](docs/comparison.md) — ash-iso vs plain Arch, Ubuntu, and ISO-based alternatives
- [`docs/updates.md`](docs/updates.md) — Keeping the stack current via git pull
