#!/usr/bin/env python3
"""Web research tool — fetches web content and indexes it into Qdrant for AI context."""

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
COLLECTION = "web_context"
MODEL = os.environ.get("ASH_MODEL", "nomic-embed-text")
DEFAULT_LIMIT = 5
HEADERS = {"Content-Type": "application/json"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("web-research")

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
    log.error("Failed to create web context collection")

def search_web(query, limit=DEFAULT_LIMIT):
    return []

def fetch_url_content(url):
    try:
        r = requests.get(url, timeout=15, headers={"User-Agent": "Ash/1.0"})
        if r.status_code == 200:
            text = r.text
            return {"url": url, "title": "", "content": text[:15000]}
    except Exception as e:
        log.warning(f"Failed to fetch {url}: {e}")
    return None

def clean_html(text):
    import re
    text = re.sub(r'<script[^>]*>.*?</script>', ' ', text, flags=re.DOTALL)
    text = re.sub(r'<style[^>]*>.*?</style>', ' ', text, flags=re.DOTALL)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

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

def index_content(source_name, content_text, metadata=None):
    if not content_text or len(content_text.strip()) == 0:
        return 0
    chunks = [content_text[i:i+512] for i in range(0, len(content_text), 512)]
    indexed = 0
    for chunk_idx, chunk in enumerate(chunks):
        vec = embed_text(chunk)
        if not vec:
            continue
        chunk_id = hashlib.md5(f"{source_name}:{chunk_idx}".encode()).hexdigest()
        payload = {
            "points": [{
                "id": chunk_id,
                "vector": vec,
                "payload": {
                    "source": "web",
                    "source_name": source_name,
                    "chunk_index": chunk_idx,
                    "text": chunk[:200],
                    "type": "web",
                    **(metadata or {}),
                }
            }]
        }
        try:
            r = requests.put(
                f"{QDRANT_URL}/collections/{COLLECTION}/points",
                json=payload, timeout=10, headers=HEADERS
            )
            if r.status_code in (200, 201):
                indexed += 1
        except Exception as e:
            log.warning(f"Failed to index chunk {chunk_idx}: {e}")
    return indexed

def research(query, limit=DEFAULT_LIMIT):
    ensure_collection()
    results = search_web(query, limit)
    if not results:
        log.info("No search results found (web search not configured)")
        return 0
    total = 0
    for result in results:
        content = fetch_url_content(result.get("url", ""))
        if content:
            content["content"] = clean_html(content.get("content", ""))
            count = index_content(content.get("title", result.get("url", "")), content.get("content", ""), {
                "url": result.get("url", ""),
                "title": content.get("title", ""),
            })
            total += count
    log.info(f"Research complete: {total} chunks indexed for '{query}'")
    return total

def search_context(query, limit=5):
    ensure_collection()
    vec = embed_text(query)
    if not vec:
        return []
    payload = {"vector": vec, "limit": limit, "with_payload": True}
    try:
        r = requests.post(
            f"{QDRANT_URL}/collections/{COLLECTION}/points/search",
            json=payload, timeout=10, headers=HEADERS
        )
        if r.status_code == 200:
            results = r.json().get("result", [])
            return [{"score": hit["score"], "payload": hit["payload"]} for hit in results]
    except Exception as e:
        log.warning(f"Search failed: {e}")
    return []

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "research":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        limit = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_LIMIT
        if query:
            research(query, limit)
        else:
            log.error("Usage: web-research research <query> [limit]")
            sys.exit(1)
    elif len(sys.argv) > 1 and sys.argv[1] == "search":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        limit = int(sys.argv[3]) if len(sys.argv) > 3 else 5
        results = search_context(query, limit)
        print(json.dumps(results, indent=2))
    else:
        log.error("Usage: web-research research <query> | web-research search <query>")
        sys.exit(1)