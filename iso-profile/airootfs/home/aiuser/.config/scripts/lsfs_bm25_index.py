#!/usr/bin/env python3
"""
lsfs_bm25_index.py — Build/update the BM25 keyword search index for LSFS.
This is called by the lsfs daemon after indexing files into Qdrant.
Stores file chunks in SQLite FTS5 for BM25 keyword retrieval (Item 10).
Also stores importance scores for cross-session memory persistence (Item 11).

Usage:
    python3 lsfs_bm25_index.py --init        # create DB
    python3 lsfs_bm25_index.py --add PATH    # add/update a file
    python3 lsfs_bm25_index.py --remove PATH # remove a file
    python3 lsfs_bm25_index.py --rebuild     # full re-index of watched dirs
"""

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

# Import the AST chunker from same directory
sys.path.insert(0, str(Path(__file__).parent))
try:
    from lsfs_chunker import chunk_file
except ImportError:
    def chunk_file(path, **kwargs):  # type: ignore
        """Fallback: plain text chunking if chunker not available."""
        try:
            text = Path(path).read_text(errors="replace")[:8192]
        except Exception:
            return []
        return [{"text": text, "chunk_type": "plain", "importance": 1.0,
                 "file_path": str(path), "chunk_hash": ""}]

BM25_DB = Path(os.environ.get("ASH_BM25_DB", Path.home() / ".ash" / "bm25.db"))

WATCH_DIRS = [
    Path.home() / ".config",
    Path.home() / "ash-iso" / "docs",
    Path.home() / "projects",
    Path.home() / "scripts",
]

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv",
             ".cargo", ".cache", ".local", "target", "dist", "build"}
SKIP_EXTENSIONS = {".pyc", ".pyo", ".o", ".so", ".a", ".class", ".jar",
                   ".iso", ".img", ".zip", ".tar", ".gz", ".bz2", ".7z",
                   ".mp4", ".mkv", ".avi", ".png", ".jpg", ".jpeg", ".ico",
                   ".db", ".sqlite", ".lock", ".bin", ".dat"}
MAX_FILE_BYTES = 512 * 1024  # 512KB


def get_db() -> sqlite3.Connection:
    BM25_DB.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(BM25_DB))
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")
    return con


def init_db(con: sqlite3.Connection) -> None:
    con.executescript("""
        CREATE VIRTUAL TABLE IF NOT EXISTS lsfs_fts USING fts5(
            path UNINDEXED,
            name UNINDEXED,
            chunk_text,
            chunk_type UNINDEXED,
            importance UNINDEXED,
            chunk_hash UNINDEXED,
            tokenize = 'porter unicode61'
        );

        CREATE TABLE IF NOT EXISTS lsfs_file_meta (
            path TEXT PRIMARY KEY,
            mtime REAL,
            size INTEGER,
            chunk_count INTEGER,
            indexed_at REAL
        );
    """)
    con.commit()
    print(f"BM25 database initialized: {BM25_DB}")


def add_file(con: sqlite3.Connection, file_path: str) -> int:
    """Add or update all chunks for a file. Returns number of chunks indexed."""
    path = Path(file_path)
    if not path.is_file():
        return 0
    if path.stat().st_size > MAX_FILE_BYTES:
        return 0
    if path.suffix.lower() in SKIP_EXTENSIONS:
        return 0

    try:
        stat = path.stat()
    except OSError:
        return 0

    # Check if file hasn't changed since last index
    row = con.execute(
        "SELECT mtime FROM lsfs_file_meta WHERE path=?", (str(path),)
    ).fetchone()
    if row and abs(row[0] - stat.st_mtime) < 0.01:
        return 0  # Not modified

    # Remove old chunks
    remove_file(con, str(path))

    chunks = chunk_file(str(path))
    if not chunks:
        return 0

    rows = [
        (str(path), path.name, c["text"], c["chunk_type"],
         c["importance"], c.get("chunk_hash", ""))
        for c in chunks
    ]
    con.executemany(
        "INSERT INTO lsfs_fts(path, name, chunk_text, chunk_type, importance, chunk_hash) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        rows,
    )
    con.execute(
        """INSERT INTO lsfs_file_meta(path, mtime, size, chunk_count, indexed_at)
           VALUES(?, ?, ?, ?, unixepoch())
           ON CONFLICT(path) DO UPDATE SET
               mtime=excluded.mtime, size=excluded.size,
               chunk_count=excluded.chunk_count, indexed_at=excluded.indexed_at""",
        (str(path), stat.st_mtime, stat.st_size, len(chunks)),
    )
    con.commit()
    return len(chunks)


def remove_file(con: sqlite3.Connection, file_path: str) -> None:
    con.execute("DELETE FROM lsfs_fts WHERE path=?", (file_path,))
    con.execute("DELETE FROM lsfs_file_meta WHERE path=?", (file_path,))


def rebuild(con: sqlite3.Connection) -> None:
    """Full rebuild of BM25 index from watched directories."""
    print("Starting BM25 full re-index...")
    total = 0
    for watch_dir in WATCH_DIRS:
        if not watch_dir.exists():
            continue
        for root, dirs, files in os.walk(watch_dir):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for fname in files:
                fpath = Path(root) / fname
                n = add_file(con, str(fpath))
                if n > 0:
                    total += 1
                    if total % 100 == 0:
                        print(f"  Indexed {total} files...")

    # Optimize FTS index
    con.execute("INSERT INTO lsfs_fts(lsfs_fts) VALUES('optimize')")
    con.commit()
    print(f"BM25 re-index complete: {total} files")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ash LSFS BM25 index manager")
    parser.add_argument("--init", action="store_true", help="Initialize database")
    parser.add_argument("--add", metavar="PATH", help="Add/update a file")
    parser.add_argument("--remove", metavar="PATH", help="Remove a file from index")
    parser.add_argument("--rebuild", action="store_true", help="Full re-index")
    parser.add_argument("--stats", action="store_true", help="Print index statistics")
    args = parser.parse_args()

    con = get_db()
    init_db(con)

    if args.add:
        n = add_file(con, args.add)
        print(f"Indexed {n} chunks from {args.add}")
    elif args.remove:
        remove_file(con, args.remove)
        con.commit()
        print(f"Removed {args.remove} from BM25 index")
    elif args.rebuild:
        rebuild(con)
    elif args.stats:
        n_files = con.execute("SELECT COUNT(*) FROM lsfs_file_meta").fetchone()[0]
        n_chunks = con.execute("SELECT COUNT(*) FROM lsfs_fts").fetchone()[0]
        db_size = BM25_DB.stat().st_size / (1024 * 1024)
        print(f"BM25 Index: {n_files} files, {n_chunks} chunks, {db_size:.1f} MB")
    elif args.init:
        print("Database initialized.")
    else:
        parser.print_help()

    con.close()


if __name__ == "__main__":
    main()
