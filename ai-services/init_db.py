#!/usr/bin/env python3
import os
import sys
import sqlite3
from pathlib import Path

BASE = Path(__file__).parent
DATA_DIR = BASE / "data"
MEMORY_DB = DATA_DIR / "memory.db"
VECTORS_DIR = DATA_DIR / "vectors"

DATA_DIR.mkdir(parents=True, exist_ok=True)
VECTORS_DIR.mkdir(parents=True, exist_ok=True)

def init_sqlite():
    conn = sqlite3.connect(str(MEMORY_DB))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")

    conn.executescript("""
        CREATE TABLE IF NOT EXISTS prompts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            key         TEXT UNIQUE NOT NULL,
            content     TEXT NOT NULL,
            version     INTEGER DEFAULT 1,
            tags        TEXT DEFAULT '',
            created_at  REAL DEFAULT (strftime('%s','now')),
            updated_at  REAL DEFAULT (strftime('%s','now'))
        );

        CREATE TABLE IF NOT EXISTS graph_nodes (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id     TEXT UNIQUE NOT NULL,
            label       TEXT NOT NULL,
            properties  TEXT DEFAULT '{}',
            created_at  REAL DEFAULT (strftime('%s','now'))
        );

        CREATE TABLE IF NOT EXISTS graph_edges (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id   TEXT NOT NULL REFERENCES graph_nodes(node_id),
            target_id   TEXT NOT NULL REFERENCES graph_nodes(node_id),
            relation    TEXT NOT NULL,
            properties  TEXT DEFAULT '{}',
            created_at  REAL DEFAULT (strftime('%s','now'))
        );

        CREATE INDEX IF NOT EXISTS idx_prompts_key ON prompts(key);
        CREATE INDEX IF NOT EXISTS idx_graph_nodes_id ON graph_nodes(node_id);
        CREATE INDEX IF NOT EXISTS idx_graph_edges_source ON graph_edges(source_id);
        CREATE INDEX IF NOT EXISTS idx_graph_edges_target ON graph_edges(target_id);
    """)

    conn.commit()
    conn.close()
    return True

def init_chromadb():
    try:
        import chromadb
        client = chromadb.PersistentClient(path=str(VECTORS_DIR))
        client.get_or_create_collection(
            name="embeddings",
            metadata={"hnsw:space": "cosine"}
        )
        client.get_or_create_collection(
            name="memory",
            metadata={"hnsw:space": "cosine"}
        )
        return True
    except Exception as e:
        print(f"ChromaDB init failed: {e}", file=sys.stderr)
        return False

def main():
    print("Initializing databases...")

    if init_sqlite():
        size = MEMORY_DB.stat().st_size
        print(f"  SQLite: {MEMORY_DB} ({size} bytes) — OK")
    else:
        print("  SQLite: FAILED", file=sys.stderr)
        sys.exit(1)

    if init_chromadb():
        print(f"  ChromaDB: {VECTORS_DIR} — OK")
    else:
        print("  ChromaDB: FAILED — falling back to SQLite-only mode", file=sys.stderr)

    print("\nDB ready")

if __name__ == "__main__":
    main()
