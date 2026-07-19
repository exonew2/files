---
title: Comparison — ash vs Alternatives
description: Compare ash ISO against GitHub Codespaces, Gitpod, Dev Containers, and Manual Arch VM across features, cost, and setup time.
order: 6
---

## Quick Comparison

| Feature | **ash ISO** | Gitpod / Codespaces | Dev Containers | Manual Arch VM |
|---------|-------------|---------------------|----------------|----------------|
| **Local / Offline** | 100% | Cloud only | Local | Local |
| **Zero Config** | Boot → Code | Config needed | Dockerfile | Hours |
| **GPU / Local AI** | Native passthrough | No local GPU | Via Docker | Manual |
| **AI Tools Ready** | Ollama, llama.cpp, Qdrant, Continue | Manual | Manual | Manual |
| **Instant Rollback** | Btrfs + Snapper | N/A | N/A | Manual |
| **Supply Chain Verify** | SHA256 + minisign + cosign + SLSA | Opaque | Docker trust | Manual |
| **Boot Time** | **~45s** | 60-120s | 30-60s | Hours |
| **Cost** | **Free** | $10-50/mo | Free (Docker) | Free (time) |

## When to Use Each

| Use Case | Recommended |
|----------|-------------|
| **AI coding, local LLMs, privacy** | **ash ISO** |
| **Team collaboration, cloud CI/CD** | Codespaces / Gitpod |
| **Consistent dev env across team** | Dev Containers |
| **Learning Arch, full control** | Manual Arch VM |

## The ash Advantage

> **Download → Boot → Code. No config. No cloud. No rebuilds. Instant snapshots. Native GPU. Your hardware. Your models. Your rules.**

### Unique ash Features

1. **Btrfs Snapshots + GRUB-Btrfs** — Rollback from boot menu
2. **Qdrant Vector Memory** — AI remembers across sessions
3. **Multi-Hypervisor** — One ISO, works everywhere
4. **Supply Chain Security** — 4-way verification
5. **Zero Config** — Timezone, keyboard, user, SSH, agents all auto
