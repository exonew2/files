---
title: Comparison
description: ash-iso VM deploy vs plain Arch vs other ISOs — when to use what.
order: 6
---

| Feature | **ash-iso VM Deploy** | **Plain Arch VM** | **Other ISOs (Ubuntu/Fedora)** |
|---------|----------------------|-------------------|--------------------------------|
| **Setup time** | 1 command | Hours | 15-30 min |
| **LSFS semantic search** | Included | Manual | Not available |
| **Ollama + nomic-embed-text** | Pre-configured, pinned in VRAM | Manual install | Manual |
| **Qdrant vector store** | Standalone binary + systemd | Manual Docker/binary | Manual Docker/binary |
| **Launcher mechanism** | Pure-bash hook (curl to APIs) | Requires Python/Node | Requires Python/Node |
| **Hyprland + Catppuccin** | Pre-configured, auto-login | Manual config | Different DE |
| **VMware-first** | VMX workarounds, clipboard, display fix | Not optimized | Partial support |
| **Auto-start** | systemd + wofi on Super+Space | Manual | Varies |

## Key Differentiators

- **Pure-bash launcher hook** — no Python/Node runtime dependency for queries
- **Standalone Qdrant** — single binary, no Docker, managed via systemd
- **VMware-first** — deployment includes VMX edits, display workaround, clipboard config
- **nomic-embed-text pinned in VRAM** — consistent latency for embeddings

## When to Use

| Scenario | Recommendation |
|----------|---------------|
| Local AI semantic filesystem on VMware | **ash-iso VM deploy** |
| General Arch with Hyprland | Plain Arch (more control) |
| Quick desktop without LSFS | Ubuntu / Fedora |

## Repo

`github.com/exonew2/files` (private) — deploy script, launcher hook, and LSFS daemon.
