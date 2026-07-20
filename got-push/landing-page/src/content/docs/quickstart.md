---
title: Quick Start
description: Deploy an Arch Linux VM with LSFS semantic filesystem, Ollama, and Qdrant using a single curl command.
order: 1
---

## One-Liner Deploy

```bash
curl -sfL https://raw.githubusercontent.com/exonew2/files/main/scripts/ultimate-fix-v2.sh | sudo bash
```

That's it. The script:

1. Installs Qdrant, Ollama, LSFS daemon, and launcher hook on your existing Arch VM
2. Installs Ollama + nomic-embed-text model
3. Installs Qdrant standalone binary
4. Deploys the LSFS pure-bash launcher hook
5. Applies VMware-specific fixes (VMX workaround, clipboard, resolution)
6. Configures auto-login and auto-start on boot

## What You Get

| Component | Description |
|-----------|-------------|
| **LSFS** | Semantic filesystem — pure-bash launch helper that resolves queries via Ollama embeddings + Qdrant vector search |
| **Ollama** | Runs `nomic-embed-text` (768-dim) for embedding generation |
| **Qdrant** | Standalone binary — vector store for semantic lookups |
| **VMware** | Fusion/Workstation with optimized VMX config, clipboard, display |

## Verification

After boot:

```bash
# Check services
systemctl status ollama qdrant

# Test embedding
curl -s http://localhost:11434/api/embeddings -d '{"model": "nomic-embed-text", "prompt": "hello"}'

# Test Qdrant
curl -s http://localhost:6333/collections

# Run LSFS helper
lsfs query "find me the networking module"
```

## Requirements

- VMware Fusion (macOS) or VMware Workstation (Linux/Windows)
- 4 GB RAM minimum, 8 GB recommended
- 20 GB free disk
