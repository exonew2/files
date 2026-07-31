#!/usr/bin/env python3
"""
lsfs_chunker.py — AST-aware code chunker for Ash LSFS semantic search.
Item 9: Replace line-based chunking with tree-sitter AST parsing.
Item 11: Attach importance_score metadata for persistent cross-session memory.

Usage:
    from lsfs_chunker import chunk_file
    chunks = chunk_file("/path/to/file.py")
    # Returns list of {"text": str, "chunk_type": str, "importance": float}

Requires: tree-sitter, tree-sitter-python, tree-sitter-javascript, etc.
Install: pip install tree-sitter tree-sitter-languages
"""

import hashlib
import mimetypes
import os
from pathlib import Path
from typing import Any

# ── Importance scoring weights ────────────────────────────────────────────────
# Item 11: Files/chunks from certain paths get higher importance scores so they
# persist strongly in the Qdrant memory across sessions.
IMPORTANCE_BOOST_PATHS = {
    ".config": 1.2,
    "docs": 1.3,
    "README": 1.5,
    "CHANGELOG": 1.4,
    "ARCHITECTURE": 1.5,
    "decisions": 1.6,   # ADR files
    "rfcs": 1.6,
}

IMPORTANCE_CHUNK_TYPES = {
    "class_definition": 1.4,
    "function_definition": 1.2,
    "module_docstring": 1.5,
    "comment_block": 1.1,
    "plain": 1.0,
}

MAX_CHUNK_BYTES = 1500  # target chunk size for embedding
OVERLAP_LINES = 3       # line overlap between adjacent plain chunks


def _importance_for_path(path: Path) -> float:
    """Compute base importance multiplier for a file path."""
    score = 1.0
    path_str = str(path).lower()
    for keyword, boost in IMPORTANCE_BOOST_PATHS.items():
        if keyword.lower() in path_str:
            score = max(score, boost)
    return score


def _importance_for_chunk(chunk_type: str, path_importance: float) -> float:
    """Final importance = path importance × chunk-type weight, capped at 2.0."""
    type_weight = IMPORTANCE_CHUNK_TYPES.get(chunk_type, 1.0)
    return min(round(path_importance * type_weight, 3), 2.0)


# ── AST-based chunking ────────────────────────────────────────────────────────

def _try_ast_chunk(source: str, language: str) -> list[dict[str, Any]] | None:
    """
    Attempt tree-sitter AST chunking. Returns None if tree-sitter is not
    installed or the language grammar is unavailable — caller falls back to
    plain line chunking.
    """
    try:
        from tree_sitter_languages import get_language, get_parser  # type: ignore
    except ImportError:
        return None

    try:
        lang = get_language(language)
        parser = get_parser(language)
    except Exception:
        return None

    tree = parser.parse(source.encode())
    root = tree.root_node
    chunks: list[dict[str, Any]] = []
    lines = source.splitlines(keepends=True)

    # Module-level docstring (Python only)
    if language == "python" and root.children:
        first = root.children[0]
        if first.type == "expression_statement":
            child = first.children[0] if first.children else None
            if child and child.type in ("string", "concatenated_string"):
                text = source[first.start_byte:first.end_byte]
                chunks.append({"text": text.strip(), "chunk_type": "module_docstring"})

    # Walk top-level definitions
    for node in root.children:
        if node.type in (
            "function_definition", "async_function_def",
            "class_definition",
            "function_declaration", "method_definition",  # JS/TS
            "impl_item", "fn_item", "struct_item",         # Rust
        ):
            chunk_type = "class_definition" if "class" in node.type else "function_definition"
            text = source[node.start_byte:node.end_byte]

            # If the chunk is too large, split it at the method level
            if len(text.encode()) > MAX_CHUNK_BYTES * 2:
                sub_chunks = _split_large_node(source, node, chunk_type)
                chunks.extend(sub_chunks)
            else:
                chunks.append({"text": text.strip(), "chunk_type": chunk_type})

    return chunks if chunks else None


def _split_large_node(source: str, node: Any, parent_type: str) -> list[dict[str, Any]]:
    """Split a large class/impl into its child methods."""
    chunks = []
    for child in node.children:
        if child.type in (
            "function_definition", "async_function_def",
            "method_definition", "fn_item",
        ):
            text = source[child.start_byte:child.end_byte]
            chunks.append({"text": text.strip(), "chunk_type": "function_definition"})
    # Fallback: include the whole node if no methods extracted
    if not chunks:
        chunks.append({"text": source[node.start_byte:node.end_byte].strip(),
                       "chunk_type": parent_type})
    return chunks


def _plain_chunk(text: str) -> list[dict[str, Any]]:
    """
    Simple line-based chunker as fallback when tree-sitter is unavailable.
    Uses sliding-window with OVERLAP_LINES overlap between chunks.
    """
    lines = text.splitlines()
    chunks = []
    i = 0
    while i < len(lines):
        chunk_lines = []
        byte_count = 0
        j = i
        while j < len(lines) and byte_count < MAX_CHUNK_BYTES:
            chunk_lines.append(lines[j])
            byte_count += len(lines[j].encode())
            j += 1
        if chunk_lines:
            chunks.append({"text": "\n".join(chunk_lines).strip(), "chunk_type": "plain"})
        i = max(i + 1, j - OVERLAP_LINES)
    return chunks


# ── Language detection ────────────────────────────────────────────────────────

EXTENSION_LANGUAGE = {
    ".py": "python", ".pyi": "python",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".ts": "typescript", ".tsx": "typescript",
    ".rs": "rust",
    ".go": "go",
    ".c": "c", ".h": "c",
    ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp", ".hpp": "cpp",
    ".java": "java",
    ".rb": "ruby",
    ".sh": "bash", ".bash": "bash", ".zsh": "bash",
    ".lua": "lua",
    ".toml": None,  # config — use plain chunking
    ".yaml": None, ".yml": None,
    ".json": None,
    ".md": None, ".rst": None, ".txt": None,
}


def _detect_language(path: Path) -> str | None:
    return EXTENSION_LANGUAGE.get(path.suffix.lower())


# ── Public API ────────────────────────────────────────────────────────────────

def chunk_file(file_path: str | Path, max_bytes: int = 8192) -> list[dict[str, Any]]:
    """
    Chunk a file into semantically meaningful pieces for embedding.

    Returns a list of dicts:
        {
            "text": str,           # the chunk content
            "chunk_type": str,     # "function_definition" | "class_definition" | "plain" | ...
            "importance": float,   # 0.0–2.0 — higher = more important for memory
            "file_path": str,
            "chunk_hash": str,     # sha256 of chunk text for deduplication
        }
    """
    path = Path(file_path)
    path_importance = _importance_for_path(path)

    try:
        raw = path.read_bytes()
        if len(raw) > max_bytes:
            raw = raw[:max_bytes]
        text = raw.decode("utf-8", errors="replace")
    except (OSError, PermissionError):
        return []

    language = _detect_language(path)
    raw_chunks: list[dict[str, Any]] | None = None

    if language:
        raw_chunks = _try_ast_chunk(text, language)

    if not raw_chunks:
        # Fallback: plain line-based chunking
        raw_chunks = _plain_chunk(text)

    result = []
    for c in raw_chunks:
        chunk_text = c["text"]
        if not chunk_text.strip():
            continue
        importance = _importance_for_chunk(c["chunk_type"], path_importance)
        result.append({
            "text": chunk_text,
            "chunk_type": c["chunk_type"],
            "importance": importance,
            "file_path": str(path),
            "chunk_hash": hashlib.sha256(chunk_text.encode()).hexdigest()[:16],
        })

    return result


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: lsfs_chunker.py <file>")
        sys.exit(1)
    for chunk in chunk_file(sys.argv[1]):
        print(f"[{chunk['chunk_type']}] importance={chunk['importance']}")
        print(chunk["text"][:200])
        print("---")
