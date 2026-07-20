---
title: Comparison
description: How the ash-iso VM deployment compares to manual Arch setup, other VM images, and cloud alternatives.
order: 6
---

| Feature | **ash-iso VM** | Manual Arch VM | Ubuntu Desktop | Cloud Codespaces |
|---------|---------------|----------------|----------------|-----------------|
| **Setup Time** | 1 command | Hours | 15 min | 5 min |
| **Local / Offline** | Yes | Yes | Yes | No |
| **LSFS Semantic FS** | Included | Manual | Manual | No |
| **Ollama + Embeddings** | Pre-configured | Manual | Manual | Possible |
| **Qdrant Vector Store** | Standalone binary | Manual | Manual | No |
| **VMware Optimized** | Yes | You build it | Partial | N/A |
| **Cost** | Free | Free (time) | Free | $10-50/mo |

## When to Use

| Use Case | Recommended |
|----------|-------------|
| Local AI development with semantic search | **ash-iso VM** |
| Full control over Arch environment | Manual Arch VM |
| General-purpose Linux desktop | Ubuntu / Fedora |
| Team collaboration, cloud CI/CD | Codespaces / Gitpod |

## Key Differentiators

- **Pure-bash LSFS hook** — no Python runtime dependency
- **nomic-embed-text** — lightweight 768-dim embeddings
- **Qdrant standalone** — no Docker needed, single binary
- **VM-only deployment** — no bare-metal install, no dual-boot
