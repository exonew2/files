#!/usr/bin/env python3
"""Project MCP Server — local NotebookLM-like context database for ash-iso project."""

import json
import sys
import os
import hashlib
import re
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(os.environ.get("ASH_PROJECT_ROOT", "/Users/shrey/ash-iso"))
IGNORE_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".cache", "dist", "build", "target"}
IGNORE_FILES = {".DS_Store", ".gitignore", "package-lock.json", "yarn.lock", "*.pyc"}
MAX_FILE_SIZE = 1_048_576  # 1MB

# NotebookLM config
NOTEBOOKLM_NOTEBOOKS = os.environ.get("NOTEBOOKLM_NOTEBOOKS", "").split(",")
NOTEBOOKLM_CACHE_DIR = Path(os.environ.get("NOTEBOOKLM_CACHE_DIR", "/tmp/ash-notebooklm-cache"))

# File index cache
_file_index = {}
_project_context = {}
_notebook_cache = {}


def index_project():
    """Index all project files for context search."""
    global _file_index, _project_context, PROJECT_ROOT
    PROJECT_ROOT = Path(os.environ.get("ASH_PROJECT_ROOT", "/Users/shrey/ash-iso"))
    _file_index = {}
    _project_context = {}

    print(f"Indexing project at {PROJECT_ROOT}...", file=sys.stderr)
    print(f"Exists: {PROJECT_ROOT.exists()}, Is dir: {PROJECT_ROOT.is_dir()}", file=sys.stderr)

    count = 0
    for root, dirs, files in os.walk(PROJECT_ROOT):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS and not d.startswith(".")]

        for f in files:
            if any(f.endswith(ext) for ext in [".pyc", ".pyo"]):
                continue
            if f in IGNORE_FILES:
                continue

            fp = Path(root) / f
            rel = fp.relative_to(PROJECT_ROOT)

            try:
                stat = fp.stat()
                if stat.st_size == 0 or stat.st_size > MAX_FILE_SIZE:
                    continue

                content = fp.read_text(errors="replace")[:5000]
                if not content.strip():
                    continue

                _file_index[str(rel)] = {
                    "path": str(rel),
                    "name": f,
                    "ext": fp.suffix.lower(),
                    "size": stat.st_size,
                    "mtime": int(stat.st_mtime),
                    "content": content,
                    "lines": content.count("\n") + 1,
                }
                count += 1
                if count <= 3:
                    print(f"  Indexed: {rel}", file=sys.stderr)
            except Exception as e:
                print(f"  Error indexing {fp}: {e}", file=sys.stderr)

    print(f"Indexed {len(_file_index)} files", file=sys.stderr)

    # Build project context
    _project_context = {
        "name": "ash-iso",
        "description": "Ash Linux — Personal AI Operating System",
        "root": str(PROJECT_ROOT),
        "total_files": len(_file_index),
        "components": {},
    }

    # Categorize files
    for path, info in _file_index.items():
        ext = info["ext"]
        category = "other"

        if ext in [".sh", ".bash"]:
            category = "scripts"
        elif ext in [".py", ".py3"]:
            category = "python"
        elif ext in [".js", ".ts", ".jsx", ".tsx"]:
            category = "javascript"
        elif ext in [".md", ".rst", ".txt"]:
            category = "docs"
        elif ext in [".json", ".yaml", ".yml", ".toml"]:
            category = "config"
        elif ext in [".html", ".css", ".scss"]:
            category = "web"
        elif path.startswith("scripts/"):
            category = "scripts"
        elif path.startswith("ai-services/"):
            category = "ai-services"
        elif path.startswith("landing-page/"):
            category = "web"
        elif path.startswith("docs/"):
            category = "docs"
        elif path.startswith("packer/"):
            category = "infra"
        elif path.startswith("terraform/"):
            category = "infra"

        if category not in _project_context["components"]:
            _project_context["components"][category] = []
        _project_context["components"][category].append(path)


def load_notebooks():
    """Load notebook content from cache files."""
    global _notebook_cache
    _notebook_cache = {}
    NOTEBOOKLM_CACHE_DIR.mkdir(parents=True, exist_ok=True)

    for nb_id in NOTEBOOKLM_NOTEBOOKS:
        nb_id = nb_id.strip()
        if not nb_id:
            continue
        cache_file = NOTEBOOKLM_CACHE_DIR / f"{nb_id}.json"
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                _notebook_cache[nb_id] = data
                print(f"  Loaded notebook: {data.get('title', nb_id)}", file=sys.stderr)
            except Exception as e:
                print(f"  Error loading notebook {nb_id}: {e}", file=sys.stderr)

    # Also load any .json files in cache dir
    for f in NOTEBOOKLM_CACHE_DIR.glob("*.json"):
        nb_id = f.stem
        if nb_id not in _notebook_cache:
            try:
                data = json.loads(f.read_text())
                _notebook_cache[nb_id] = data
                print(f"  Loaded notebook: {data.get('title', nb_id)}", file=sys.stderr)
            except Exception as e:
                print(f"  Error loading notebook {nb_id}: {e}", file=sys.stderr)


def search_notebooks(query, limit=5):
    """Search notebook content."""
    results = []
    query_lower = query.lower()

    for nb_id, nb_data in _notebook_cache.items():
        title = nb_data.get("title", nb_id)
        sources = nb_data.get("sources", [])

        for source in sources:
            source_name = source.get("title", "unknown")
            content = source.get("content", "") or source.get("text", "")
            if not content:
                continue

            content_lower = content.lower()
            if query_lower in content_lower:
                score = content_lower.count(query_lower) / max(len(content_lower), 1)

                # Extract matching chunks
                chunks = [content[i:i+500] for i in range(0, len(content), 500)]
                matching_chunks = []
                for chunk in chunks:
                    if query_lower in chunk.lower():
                        matching_chunks.append(chunk[:300])
                        if len(matching_chunks) >= 2:
                            break

                results.append({
                    "notebook_id": nb_id,
                    "notebook_title": title,
                    "source_name": source_name,
                    "score": score,
                    "matching_chunks": matching_chunks,
                })

    results.sort(key=lambda x: x["score"], reverse=True)
    return results[:limit]


def search_files(query, limit=10):
    """Search project files by content."""
    results = []
    query_lower = query.lower()

    for path, info in _file_index.items():
        content_lower = info["content"].lower()
        if query_lower in content_lower:
            # Calculate relevance score
            score = content_lower.count(query_lower) / max(len(content_lower), 1)

            # Extract matching lines
            lines = info["content"].split("\n")
            matching_lines = []
            for i, line in enumerate(lines, 1):
                if query_lower in line.lower():
                    matching_lines.append({"line": i, "text": line.strip()[:200]})
                    if len(matching_lines) >= 3:
                        break

            results.append({
                "path": path,
                "name": info["name"],
                "score": score,
                "matching_lines": matching_lines,
                "size": info["size"],
                "lines": info["lines"],
            })

    results.sort(key=lambda x: x["score"], reverse=True)
    return results[:limit]


def search_all(query, limit=10):
    """Search across all sources (files + notebooks)."""
    file_results = search_files(query, limit)
    notebook_results = search_notebooks(query, limit)

    # Combine and sort by score
    all_results = []
    for r in file_results:
        all_results.append({"type": "file", **r})
    for r in notebook_results:
        all_results.append({"type": "notebook", **r})

    all_results.sort(key=lambda x: x.get("score", 0), reverse=True)
    return all_results[:limit]


def get_file_content(path):
    """Get content of a specific file."""
    if path in _file_index:
        return _file_index[path]
    return None


def get_project_context():
    """Get overall project context."""
    return _project_context


def get_component_files(component):
    """Get files for a specific component."""
    return _project_context.get("components", {}).get(component, [])


def list_components():
    """List all project components."""
    return {k: len(v) for k, v in _project_context.get("components", {}).items()}


def mcp_response(result, error=None):
    """Create MCP response."""
    return {"jsonrpc": "2.0", "result": result, "error": error, "id": None}


def handle_list_tools():
    """List available MCP tools."""
    return [
        {
            "name": "search_project",
            "description": "Search project files by content (like NotebookLM search)",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "limit": {"type": "integer", "description": "Max results (default: 10)"},
                },
                "required": ["query"],
            },
        },
        {
            "name": "search_notebooks",
            "description": "Search NotebookLM notebook content",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "limit": {"type": "integer", "description": "Max results (default: 5)"},
                },
                "required": ["query"],
            },
        },
        {
            "name": "get_file",
            "description": "Get content of a specific project file",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "File path relative to project root"},
                },
                "required": ["path"],
            },
        },
        {
            "name": "get_context",
            "description": "Get overall project context (components, structure, stats)",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "list_components",
            "description": "List all project components and their file counts",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "get_component",
            "description": "Get files for a specific component (scripts, docs, ai-services, etc.)",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "component": {"type": "string", "description": "Component name"},
                },
                "required": ["component"],
            },
        },
        {
            "name": "list_notebooks",
            "description": "List all loaded NotebookLM notebooks",
            "inputSchema": {"type": "object", "properties": {}},
        },
    ]


def handle_call_tool(name, arguments):
    """Handle MCP tool calls."""
    if name == "search_project":
        query = arguments.get("query", "")
        limit = arguments.get("limit", 10)
        results = search_files(query, limit)
        if not results:
            return [{"type": "text", "text": f"No files found matching '{query}'"}]
        output = f"Search results for '{query}':\n\n"
        for i, r in enumerate(results, 1):
            output += f"[{i}] {r['path']} ({r['lines']} lines)\n"
            for line in r["matching_lines"]:
                output += f"    L{line['line']}: {line['text']}\n"
            output += "\n"
        return [{"type": "text", "text": output}]

    elif name == "get_file":
        path = arguments.get("path", "")
        info = get_file_content(path)
        if not info:
            return [{"type": "text", "text": f"File not found: {path}"}]
        output = f"File: {info['path']}\n"
        output += f"Size: {info['size']} bytes, {info['lines']} lines\n\n"
        output += info["content"]
        return [{"type": "text", "text": output}]

    elif name == "get_context":
        ctx = get_project_context()
        output = f"Project: {ctx['name']}\n"
        output += f"Description: {ctx['description']}\n"
        output += f"Root: {ctx['root']}\n"
        output += f"Total files indexed: {ctx['total_files']}\n\n"
        output += "Components:\n"
        for comp, files in ctx.get("components", {}).items():
            output += f"  - {comp}: {len(files)} files\n"
        return [{"type": "text", "text": output}]

    elif name == "list_components":
        comps = list_components()
        output = "Project components:\n"
        for comp, count in comps.items():
            output += f"  - {comp}: {count} files\n"
        return [{"type": "text", "text": output}]

    elif name == "get_component":
        component = arguments.get("component", "")
        files = get_component_files(component)
        if not files:
            available = list_components().keys()
            return [{"type": "text", "text": f"Component '{component}' not found. Available: {', '.join(available)}"}]
        output = f"Component '{component}' files:\n\n"
        for f in files[:50]:
            info = _file_index.get(f, {})
            output += f"  {f} ({info.get('lines', '?')} lines)\n"
        if len(files) > 50:
            output += f"\n  ... and {len(files) - 50} more files"
        return [{"type": "text", "text": output}]

    elif name == "search_notebooks":
        query = arguments.get("query", "")
        limit = arguments.get("limit", 5)
        results = search_notebooks(query, limit)
        if not results:
            return [{"type": "text", "text": f"No notebook content found matching '{query}'"}]
        output = f"Notebook search results for '{query}':\n\n"
        for i, r in enumerate(results, 1):
            output += f"[{i}] {r['notebook_title']} → {r['source_name']} (score: {r['score']:.3f})\n"
            for chunk in r["matching_chunks"]:
                output += f"    {chunk[:200]}...\n"
            output += "\n"
        return [{"type": "text", "text": output}]

    elif name == "list_notebooks":
        if not _notebook_cache:
            return [{"type": "text", "text": "No notebooks loaded. Set NOTEBOOKLM_NOTEBOOKS env var or add .json files to /tmp/ash-notebooklm-cache/"}]
        output = "Loaded NotebookLM notebooks:\n\n"
        for nb_id, nb_data in _notebook_cache.items():
            title = nb_data.get("title", nb_id)
            sources = nb_data.get("sources", [])
            output += f"  - {title} ({nb_id})\n"
            output += f"    Sources: {len(sources)}\n"
            for s in sources[:3]:
                output += f"      - {s.get('title', 'unknown')}\n"
            if len(sources) > 3:
                output += f"      ... and {len(sources) - 3} more sources\n"
            output += "\n"
        return [{"type": "text", "text": output}]

    else:
        return [{"type": "text", "text": f"Unknown tool: {name}"}]


def handle_list_resources():
    """List available MCP resources."""
    resources = []
    for path in _file_index:
        resources.append({
            "uri": f"project://file/{path}",
            "name": path,
            "mimeType": "text/plain",
        })
    return resources


def handle_read_resource(uri):
    """Read an MCP resource."""
    parts = uri.split("/")
    if len(parts) >= 4 and parts[2] == "file":
        path = "/".join(parts[3:])
        info = get_file_content(path)
        if info:
            return info["content"]
    return "Resource not found"


def main():
    """Main MCP server loop."""
    # Index project on startup
    index_project()
    load_notebooks()

    capabilities = {
        "resources": {"listChanged": True},
        "tools": {},
    }

    # Write startup info to stderr (not stdout)
    print(f"Project MCP server started. Indexed {_project_context['total_files']} files.", file=sys.stderr)

    while True:
        line = sys.stdin.readline()
        if not line:
            break

        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = msg.get("method", "")
        params = msg.get("params", {})

        if method == "initialize":
            response = mcp_response({
                "protocolVersion": "2024-11-05",
                "capabilities": capabilities,
                "serverInfo": {
                    "name": "ash-project-mcp",
                    "version": "1.0.0",
                },
            })
            print(json.dumps(response), flush=True)

        elif method == "resources/list":
            response = mcp_response({"resources": handle_list_resources()})
            print(json.dumps(response), flush=True)

        elif method == "resources/read":
            content = handle_read_resource(params.get("uri", ""))
            response = mcp_response({"contents": [content]})
            print(json.dumps(response), flush=True)

        elif method == "tools/list":
            response = mcp_response({"tools": handle_list_tools()})
            print(json.dumps(response), flush=True)

        elif method == "tools/call":
            result = handle_call_tool(params.get("name", ""), params.get("arguments", {}))
            response = mcp_response({"content": result})
            print(json.dumps(response), flush=True)

        elif method == "ping":
            print(json.dumps(mcp_response({"ok": True})), flush=True)

        else:
            response = mcp_response(None, {"code": -32601, "message": f"Unknown method: {method}"})
            print(json.dumps(response), flush=True)


if __name__ == "__main__":
    main()