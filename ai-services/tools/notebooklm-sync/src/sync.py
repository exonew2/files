#!/usr/bin/env python3
"""NotebookLM sync daemon — exports NotebookLM notebook content into Qdrant for AI context."""

import os
import sys
import json
import time
import hashlib
import logging
import requests
from pathlib import Path

HOME = os.environ.get("HOME", "/home/shrey")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/embeddings")
NOTEBOOKLM_API = os.environ.get("NOTEBOOKLM_API", "http://localhost:3000")
COLLECTION = "notebooklm_context"
MODEL = os.environ.get("ASH_MODEL", "nomic-embed-text")
POLL_INTERVAL = int(os.environ.get("NOTEBOOKLM_POLL", "300"))
SYNC_DIR = Path(os.environ.get("NOTEBOOKLM_SYNC_DIR", f"{HOME}/.ash/notebooklm"))
HEADERS = {"Content-Type": "application/json"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("notebooklm-sync")

def ensure_collection():
    r = requests.get(f"{QDRANT_URL}/collections/{COLLECTION}", timeout=5)
    if r.status_code == 200:
        return
    payload = {"vectors": {"size": 768, "distance": "Cosine"}}
    for i in range(5):
        r = requests.put(f"{QDRANT_URL}/collections/{COLLECTION}", json=payload, timeout=10)
        if r.status_code in (200, 201):
            log.info(f"Collection '{COLLECTION}' created")
            return
        time.sleep(2)
    log.error("Failed to create NotebookLM collection")

def get_notebooks():
    try:
        r = requests.get(f"{NOTEBOOKLM_API}/api/notebooks", timeout=10)
        if r.status_code == 200:
            return r.json().get("notebooks", [])
    except Exception as e:
        log.warning(f"NotebookLM API unreachable: {e}")
    return []

def get_notebook_content(notebook_id):
    try:
        r = requests.get(f"{NOTEBOOKLM_API}/api/notebooks/{notebook_id}/content", timeout=30)
        if r.status_code == 200:
            return r.json()
    except Exception as e:
        log.warning(f"Failed to fetch notebook {notebook_id}: {e}")
    return None

def embed_text(text):
    if not text or len(text.strip()) == 0:
        return None
    payload = {"model": MODEL, "prompt": text[:2048], "keep_alive": -1}
    for i in range(3):
        try:
            r = requests.post(OLLAMA_URL, json=payload, timeout=30)
            if r.status_code == 200:
                data = r.json()
                if "embedding" in data:
                    return data["embedding"]
        except Exception:
            pass
        time.sleep(1)
    return None

def sync_notebook(notebook):
    nb_id = notebook.get("id")
    nb_title = notebook.get("title", "untitled")
    log.info(f"Syncing notebook: {nb_title}")

    content = get_notebook_content(nb_id)
    if not content:
        return 0

    chunks_indexed = 0
    sources = content.get("sources", [])
    for source in sources:
        source_name = source.get("title", "unknown")
        source_text = source.get("content", "") or source.get("text", "")
        if not source_text:
            continue

        chunks = [source_text[i:i+512] for i in range(0, len(source_text), 512)]
        for chunk_idx, chunk in enumerate(chunks):
            vec = embed_text(chunk)
            if not vec:
                continue
            chunk_id = hashlib.md5(f"{nb_id}:{source_name}:{chunk_idx}".encode()).hexdigest()
            payload = {
                "points": [{
                    "id": chunk_id,
                    "vector": vec,
                    "payload": {
                        "source": "notebooklm",
                        "notebook_id": nb_id,
                        "notebook_title": nb_title,
                        "source_name": source_name,
                        "chunk_index": chunk_idx,
                        "text": chunk[:200],
                        "type": "notebooklm",
                    }
                }]
            }
            try:
                r = requests.put(
                    f"{QDRANT_URL}/collections/{COLLECTION}/points",
                    json=payload, timeout=10, headers=HEADERS
                )
                if r.status_code in (200, 201):
                    chunks_indexed += 1
            except Exception as e:
                log.warning(f"Failed to index chunk {chunk_idx}: {e}")

    log.info(f"Synced '{nb_title}': {chunks_indexed} chunks indexed")
    return chunks_indexed

def run_sync():
    ensure_collection()
    SYNC_DIR.mkdir(parents=True, exist_ok=True)

    notebooks = get_notebooks()
    if not notebooks:
        log.info("No notebooks found or NotebookLM API unavailable")
        return

    total = 0
    for nb in notebooks:
        total += sync_notebook(nb)

    log.info(f"Sync complete: {total} chunks indexed from {len(notebooks)} notebooks")

def run_daemon():
    log.info("NotebookLM sync daemon starting (poll every %ds)", POLL_INTERVAL)
    while True:
        try:
            run_sync()
        except Exception as e:
            log.error(f"Sync error: {e}")
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--daemon":
        run_daemon()
    else:
        run_sync()