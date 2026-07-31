#!/usr/bin/env python3
"""NotebookLM MCP Server — exposes NotebookLM as an MCP server for AI agents."""

import json
import sys
import os
import requests
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("notebooklm-mcp")

NOTEBOOKLM_API = os.environ.get("NOTEBOOKLM_API", "http://localhost:3000")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333")
QDRANT_API_KEY = os.environ.get("QDRANT_API_KEY", "")
COLLECTION = "notebooklm_context"
HEADERS = {"Content-Type": "application/json"}
if QDRANT_API_KEY:
    HEADERS["api-key"] = QDRANT_API_KEY


def mcp_response(result, error=None):
    return {"jsonrpc": "2.0", "result": result, "error": error, "id": None}


def list_notebooks():
    try:
        r = requests.get(f"{NOTEBOOKLM_API}/api/notebooks", timeout=10)
        if r.status_code == 200:
            return r.json().get("notebooks", [])
    except Exception as e:
        log.warning("NotebookLM API unreachable: %s", e)
    return []


def get_notebook_content(notebook_id):
    try:
        r = requests.get(f"{NOTEBOOKLM_API}/api/notebooks/{notebook_id}/content", timeout=30)
        if r.status_code == 200:
            return r.json()
    except Exception as e:
        log.warning("Failed to fetch notebook %s: %s", notebook_id, e)
    return None


def search_notebooks(query):
    vec = embed_text(query)
    if not vec:
        return []
    try:
        r = requests.post(
            f"{QDRANT_URL}/collections/{COLLECTION}/points/search",
            json={"vector": vec, "limit": 10, "with_payload": True},
            headers=HEADERS, timeout=10,
        )
        if r.status_code == 200:
            return [{"score": h.get("score", 0), "payload": h.get("payload", {})} for h in r.json().get("result", [])]
    except Exception as e:
        log.warning("Search failed: %s", e)
    return []


def embed_text(text):
    OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434/api/embeddings")
    MODEL = os.environ.get("ASH_MODEL", "nomic-embed-text")
    payload = {"model": MODEL, "prompt": text[:2048], "keep_alive": -1}
    for _ in range(3):
        try:
            r = requests.post(OLLAMA_URL, json=payload, timeout=30)
            if r.status_code == 200:
                d = r.json()
                if "embedding" in d:
                    return d["embedding"]
        except Exception:
            pass
    return None


def handle_list_resources():
    notebooks = list_notebooks()
    resources = []
    for nb in notebooks:
        resources.append({
            "uri": f"notebooklm://notebook/{nb.get('id', '')}",
            "name": nb.get("title", "untitled"),
            "mimeType": "text/plain",
            "description": nb.get("description", ""),
        })
    return resources


def handle_read_resource(uri):
    parts = uri.split("/")
    notebook_id = parts[-1] if parts else ""
    content = get_notebook_content(notebook_id)
    if not content:
        return {"error": f"Notebook {notebook_id} not found"}
    sources = content.get("sources", [])
    combined = "\n\n".join(s.get("content", "") or s.get("text", "") for s in sources)
    return combined[:50000]


def handle_call_tool(name, arguments):
    if name == "list_notebooks":
        notebooks = list_notebooks()
        return [{"type": "text", "text": json.dumps(notebooks, indent=2)}]
    elif name == "get_notebook":
        nb_id = arguments.get("notebook_id", "")
        content = get_notebook_content(nb_id)
        if content:
            return [{"type": "text", "text": json.dumps(content, indent=2)[:10000]}]
        return [{"type": "text", "text": f"Notebook {nb_id} not found"}]
    elif name == "search_notebooks":
        query = arguments.get("query", "")
        results = search_notebooks(query)
        return [{"type": "text", "text": json.dumps(results, indent=2)}]
    elif name == "ask_notebook":
        query = arguments.get("query", "")
        results = search_notebooks(query)
        if not results:
            return [{"type": "text", "text": "No relevant context found in notebooks."}]
        top = results[:3]
        context = "\n---\n".join(
            f"Source: {r['payload'].get('source_name', 'unknown')} (score: {r['score']:.3f})\n{r['payload'].get('text', '')[:500]}"
            for r in top
        )
        return [{"type": "text", "text": f"Context for '{query}':\n{context}"}]
    else:
        return [{"type": "text", "text": f"Unknown tool: {name}"}]


def handle_list_tools():
    return [
        {
            "name": "list_notebooks",
            "description": "List all available NotebookLM notebooks",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "get_notebook",
            "description": "Get full content of a NotebookLM notebook by ID",
            "inputSchema": {
                "type": "object",
                "properties": {"notebook_id": {"type": "string", "description": "Notebook ID"}},
                "required": ["notebook_id"],
            },
        },
        {
            "name": "search_notebooks",
            "description": "Semantic search across all NotebookLM notebooks",
            "inputSchema": {
                "type": "object",
                "properties": {"query": {"type": "string", "description": "Search query"}},
                "required": ["query"],
            },
        },
        {
            "name": "ask_notebook",
            "description": "Query NotebookLM context and get relevant passages",
            "inputSchema": {
                "type": "object",
                "properties": {"query": {"type": "string", "description": "Question or query"}},
                "required": ["query"],
            },
        },
    ]


def main():
    log.info("NotebookLM MCP server starting (stdio)")
    capabilities = {
        "resources": {"listChanged": True},
        "tools": {},
    }

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

        msg_id = msg.get("id")
        method = msg.get("method", "")
        params = msg.get("params", {})

        if method == "initialize":
            response = mcp_response({"protocolVersion": "2024-11-05", "capabilities": capabilities, "serverInfo": {"name": "notebooklm-mcp", "version": "1.0.0"}})
            print(json.dumps(response), flush=True)
        elif method == "resources/list":
            response = mcp_response({"resources": handle_list_resources()})
            print(json.dumps(response), flush=True)
        elif method == "resources/read":
            response = mcp_response({"contents": [handle_read_resource(params.get("uri", ""))]})
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
            print(json.dumps(mcp_response(None, {"code": -32601, "message": f"Unknown method: {method}"})))
            print(flush=True)


if __name__ == "__main__":
    main()