---
title: Health Checks
description: Verify your ash-iso VM deployment is running correctly — services, embeddings, vector store, and LSFS.
order: 2
---

## Service Status

```bash
systemctl status ollama
systemctl status qdrant
```

## Embedding Model

```bash
curl http://localhost:11434/api/tags
# Expected: nomic-embed-text:latest
```

Generate a test embedding:

```bash
curl -s http://localhost:11434/api/embeddings \
  -d '{"model": "nomic-embed-text", "prompt": "hello world"}' \
  | jq '.embedding | length'
# Expected: 768
```

## Qdrant

```bash
# REST API health
curl -s http://localhost:6333/healthz

# List collections
curl -s http://localhost:6333/collections | jq
```

## LSFS Semantic FS

```bash
# Check launcher hook is installed
which lsfs

# Run a semantic query
lsfs query "test query"
```

## Port Check

```bash
ss -tlnp | grep -E '11434|6333'
```

Expected:
- `:11434` — Ollama
- `:6333` — Qdrant (HTTP), `:6334` — gRPC
