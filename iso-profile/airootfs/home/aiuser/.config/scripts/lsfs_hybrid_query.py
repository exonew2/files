#!/usr/bin/env python3
"""
lsfs_hybrid_query.py — Multi-collection hybrid search for Ash LSFS.
Item 10: Dense vector search (Qdrant) fused with BM25 keyword search via RRF.
Item 11: High-importance vectors are returned with boosted rank.
Item 12: Searches both 'apps' (local files) AND 'notebooklm_context' (notebook knowledge).

Usage:
    python3 lsfs_hybrid_query.py "backup scripts"
    python3 lsfs_hybrid_query.py --mode semantic "docker setup"
    python3 lsfs_hybrid_query.py --mode keyword "auth.go"
    python3 lsfs_hybrid_query.py --mode hybrid "config files"   (default)
    python3 lsfs_hybrid_query.py --source notebooklm "architecture decisions"
    python3 lsfs_hybrid_query.py --source all "model router"
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

# ── Configuration ─────────────────────────────────────────────────────────────
OLLAMA_URL    = os.environ.get("OLLAMA_URL",    "http://localhost:11434/api/embeddings")
QDRANT_URL    = os.environ.get("QDRANT_URL",    "http://localhost:6333")
MODEL         = os.environ.get("ASH_MODEL",     "nomic-embed-text")
COLLECTION    = os.environ.get("ASH_COLLECTION", "apps")
NB_COLLECTION = os.environ.get("ASH_NB_COLLECTION", "notebooklm_context")
SEARCH_LIMIT  = int(os.environ.get("ASH_SEARCH_LIMIT", "20"))
COSINE_FLOOR  = float(os.environ.get("ASH_COSINE_FLOOR", "0.40"))

# BM25 index lives in a local SQLite FTS5 database
BM25_DB = Path(os.environ.get("ASH_BM25_DB", Path.home() / ".ash" / "bm25.db"))

# RRF fusion constant (higher = less sensitive to rank differences)
RRF_K = 60


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _http(method: str, url: str, body: Any = None, timeout: int = 5) -> Any:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except Exception as exc:
        return {"_error": str(exc)}


def _collection_exists(name: str) -> bool:
    r = _http("GET", f"{QDRANT_URL}/collections/{name}", timeout=3)
    return bool(r.get("result"))


# ── Embedding ─────────────────────────────────────────────────────────────────

def _get_embedding(query: str) -> list[float] | None:
    body = {"model": MODEL, "prompt": query, "keep_alive": -1}
    resp = _http("POST", OLLAMA_URL, body, timeout=8)
    return resp.get("embedding") if "_error" not in resp else None


# ── Dense semantic search (Qdrant, single collection) ────────────────────────

def _dense_search_collection(
    embedding: list[float],
    collection: str,
    limit: int,
    source_tag: str,
) -> list[dict]:
    body = {
        "vector": embedding,
        "limit": limit,
        "with_payload": True,
        "score_threshold": COSINE_FLOOR,
    }
    url = f"{QDRANT_URL}/collections/{collection}/points/search"
    resp = _http("POST", url, body, timeout=5)
    if "_error" in resp:
        return []

    results = []
    for hit in resp.get("result", []):
        p = hit.get("payload", {})
        # Normalize path field — notebooklm_context uses source_name, not path
        path = (
            p.get("path")
            or p.get("name")
            or f"notebook:{p.get('notebook_title','?')}:{p.get('source_name','?')}"
        )
        results.append({
            "path":       path,
            "name":       p.get("name") or p.get("source_name") or Path(path).name,
            "score":      hit.get("score", 0.0),
            "importance": p.get("importance", 1.0),
            "chunk_type": p.get("chunk_type", p.get("type", "plain")),
            "source":     source_tag,
            "collection": collection,
            # Extra notebook metadata for display
            "notebook_title": p.get("notebook_title", ""),
            "text_preview":   p.get("text", "")[:120],
        })
    return results


def dense_search(
    query: str,
    limit: int = SEARCH_LIMIT,
    source: str = "all",
) -> list[dict]:
    """
    Search Qdrant. source can be 'all', 'local', or 'notebooklm'.
    Always fans out to both collections when source='all', then merges.
    """
    embedding = _get_embedding(query)
    if not embedding:
        return []

    results: list[dict] = []

    if source in ("all", "local"):
        results.extend(
            _dense_search_collection(embedding, COLLECTION, limit, "dense:local")
        )

    if source in ("all", "notebooklm"):
        if _collection_exists(NB_COLLECTION):
            results.extend(
                _dense_search_collection(embedding, NB_COLLECTION, limit, "dense:notebook")
            )

    return results


# ── BM25 keyword search (SQLite FTS5, local files only) ──────────────────────

def _ensure_bm25_db() -> sqlite3.Connection | None:
    if not BM25_DB.exists():
        return None
    try:
        con = sqlite3.connect(str(BM25_DB))
        con.execute("SELECT 1 FROM lsfs_fts LIMIT 1")
        return con
    except Exception:
        return None


def bm25_search(query: str, limit: int = SEARCH_LIMIT) -> list[dict]:
    con = _ensure_bm25_db()
    if con is None:
        return []

    try:
        safe_q = query.replace('"', '""').replace("*", "").strip()
        if not safe_q:
            return []

        rows = con.execute(
            """
            SELECT path, name, chunk_text, importance,
                   bm25(lsfs_fts) AS bm25_score
            FROM lsfs_fts
            WHERE lsfs_fts MATCH ?
            ORDER BY bm25_score
            LIMIT ?
            """,
            (safe_q, limit),
        ).fetchall()
        con.close()
    except Exception:
        return []

    results = []
    for path, name, chunk_text, importance, bm25_score in rows:
        results.append({
            "path":         path,
            "name":         name or Path(path).name,
            "score":        abs(float(bm25_score)),
            "importance":   float(importance or 1.0),
            "chunk_type":   "keyword_match",
            "source":       "bm25",
            "collection":   COLLECTION,
            "notebook_title": "",
            "text_preview": (chunk_text or "")[:120],
        })
    return results


# ── Reciprocal Rank Fusion ────────────────────────────────────────────────────

def rrf_fuse(
    *result_lists: list[dict],
    k: int = RRF_K,
) -> list[dict]:
    """
    Multi-list RRF fusion.  Score(d) = Σ importance * 1/(k + rank_i(d))
    Works across any number of result lists (dense:local, dense:notebook, bm25).
    Item 11: importance multiplier ensures notebook skills/architecture docs surface.
    """
    scores: dict[str, dict] = {}

    for result_list in result_lists:
        for rank, item in enumerate(result_list, start=1):
            path = item["path"]
            importance = float(item.get("importance", 1.0))
            rrf = importance / (k + rank)

            if path not in scores:
                scores[path] = {**item, "rrf_score": 0.0, "sources": []}
            scores[path]["rrf_score"] += rrf
            scores[path]["sources"].append(item.get("source", "?"))

    return sorted(scores.values(), key=lambda x: x["rrf_score"], reverse=True)


# ── Deduplication by path ─────────────────────────────────────────────────────

def deduplicate(results: list[dict]) -> list[dict]:
    seen: set[str] = set()
    out = []
    for r in results:
        if r["path"] not in seen:
            seen.add(r["path"])
            out.append(r)
    return out


# ── Main search dispatcher ────────────────────────────────────────────────────

def search(
    query: str,
    mode: str = "hybrid",
    limit: int = SEARCH_LIMIT,
    source: str = "all",
) -> list[dict]:
    """
    source: 'all' (local + notebooklm), 'local', 'notebooklm'
    mode:   'hybrid' (dense + bm25 RRF), 'semantic' (dense only), 'keyword' (bm25 only)
    """
    if mode == "semantic":
        return deduplicate(dense_search(query, limit, source))

    elif mode == "keyword":
        # BM25 only covers local files; no keyword index for notebooklm_context
        kw = bm25_search(query, limit)
        if not kw and source in ("all", "notebooklm"):
            # Fallback: notebook collection via semantic when keyword mode is forced
            return deduplicate(dense_search(query, limit, "notebooklm"))
        return deduplicate(kw)

    else:  # hybrid (default)
        local_dense = dense_search(query, limit, "local")
        nb_dense    = (
            _dense_search_collection(
                _get_embedding(query) or [],
                NB_COLLECTION,
                limit,
                "dense:notebook",
            )
            if source in ("all", "notebooklm") and _collection_exists(NB_COLLECTION)
            else []
        ) if source != "local" else []
        keyword = bm25_search(query, limit)

        if not keyword and not nb_dense:
            # BM25 not yet populated, no notebook data — pure local semantic
            return deduplicate(local_dense)

        fused = rrf_fuse(local_dense, nb_dense, keyword)
        return deduplicate(fused)[:limit]


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Ash LSFS hybrid search")
    parser.add_argument("query", nargs="+", help="Search query")
    parser.add_argument(
        "--mode", choices=["hybrid", "semantic", "keyword"],
        default="hybrid", help="Search mode (default: hybrid)",
    )
    parser.add_argument(
        "--limit", type=int, default=SEARCH_LIMIT,
        help=f"Max results (default: {SEARCH_LIMIT})",
    )
    parser.add_argument(
        "--source", choices=["all", "local", "notebooklm"],
        default="all",
        help="Which sources to search: all (default), local files only, or notebooklm only",
    )
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    query = " ".join(args.query)
    t0 = time.time()
    results = search(query, mode=args.mode, limit=args.limit, source=args.source)
    elapsed = time.time() - t0

    if args.json:
        print(json.dumps(results, indent=2))
        return

    if not results:
        print(f"No matches found. ({elapsed:.1f}s, mode={args.mode}, src={args.source})")
        sys.exit(0)

    for r in results:
        score    = r.get("rrf_score", r.get("score", 0))
        sources  = "+".join(dict.fromkeys(r.get("sources", [r.get("source", "?")])))
        imp      = r.get("importance", 1.0)
        nb_title = f" [{r['notebook_title']}]" if r.get("notebook_title") else ""
        preview  = f"  → {r['text_preview']}" if r.get("text_preview") else ""
        print(f"{r['path']}{nb_title} (score={score:.4f}, src={sources}, imp={imp:.1f})")
        if preview:
            print(preview)

    print(f"\n({len(results)} results in {elapsed:.1f}s | mode={args.mode} | src={args.source})")


if __name__ == "__main__":
    main()
