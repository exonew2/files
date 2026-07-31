#!/usr/bin/env python3
"""
ash-model-router.py — Local dynamic model router for Ollama.
Item 19: Automatically assigns tasks to optimal models based on work type.

Runs as a lightweight HTTP proxy on 127.0.0.1:11435 that rewrites model
names before forwarding to the real Ollama on 127.0.0.1:11434.

Routing logic (configurable via /etc/ash/router.json):
  - autocomplete / short prompts  → fast small model (e.g. qwen2.5-coder:1.5b)
  - code generation               → balanced model (e.g. deepseek-coder:6.7b)
  - architecture / reasoning      → large reasoning model (e.g. qwen2.5:32b)
  - embeddings                    → nomic-embed-text (always, never rerouted)
  - default                       → configurable fallback

Usage:
  python3 ash-model-router.py                     # start on :11435
  python3 ash-model-router.py --port 11435        # explicit port
  python3 ash-model-router.py --config /etc/ash/router.json

Configure agents to hit http://localhost:11435 instead of :11434.
"""

import argparse
import http.server
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

# ── Default routing table ─────────────────────────────────────────────────────
DEFAULT_CONFIG: dict[str, Any] = {
    "ollama_url": "http://127.0.0.1:11434",
    "listen_host": "127.0.0.1",
    "listen_port": 11435,
    "log_decisions": True,

    # Embedding requests are NEVER rerouted — always use the embedding model
    "embedding_model": "nomic-embed-text",
    "embedding_endpoints": ["/api/embeddings", "/api/embed"],

    # Default model when no rule matches
    "default_model": "qwen2.5-coder:7b",

    # Routing rules (evaluated in order — first match wins)
    # Each rule: {"match": <type>, "pattern": <regex>, "model": <ollama-model>}
    "routes": [
        # Autocomplete: short prompts under 100 chars → fastest model
        {
            "name": "autocomplete",
            "match": "prompt_length_lt",
            "value": 100,
            "model": "qwen2.5-coder:1.5b"
        },
        # Architecture / reasoning questions
        {
            "name": "architecture",
            "match": "prompt_regex",
            "pattern": r"(?i)(architect|design pattern|trade.?off|system design|ADR|RFC|why did|explain|compare|best practice)",
            "model": "qwen2.5:32b"
        },
        # Security analysis
        {
            "name": "security",
            "match": "prompt_regex",
            "pattern": r"(?i)(vulnerabilit|CVE|exploit|injection|XSS|CSRF|auth|authz|privilege|sandbox|zero.?day)",
            "model": "qwen2.5:14b"
        },
        # Code generation / refactoring (medium model)
        {
            "name": "code_gen",
            "match": "prompt_regex",
            "pattern": r"(?i)(write|implement|refactor|function|class|method|generate|create|build|fix|debug|test)",
            "model": "qwen2.5-coder:7b"
        },
        # Explicit model in request: honor it (no reroute)
        {
            "name": "explicit",
            "match": "model_explicitly_set",
            "model": None  # None = keep original
        },
    ]
}

CONFIG_PATH = Path(os.environ.get("ASH_ROUTER_CONFIG", "/etc/ash/router.json"))
LOG_PATH = Path("/var/log/ash/router.log")


def load_config() -> dict[str, Any]:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                cfg = json.load(f)
            # Merge with defaults so new keys are always present
            merged = {**DEFAULT_CONFIG, **cfg}
            merged["routes"] = cfg.get("routes", DEFAULT_CONFIG["routes"])
            return merged
        except Exception as e:
            print(f"[router] Config error ({CONFIG_PATH}): {e} — using defaults", file=sys.stderr)
    return DEFAULT_CONFIG.copy()


def log_decision(entry: dict[str, Any], cfg: dict[str, Any]) -> None:
    if not cfg.get("log_decisions"):
        return
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps({**entry, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


# ── Routing logic ─────────────────────────────────────────────────────────────

def route(body: dict[str, Any], endpoint: str, cfg: dict[str, Any]) -> tuple[str, str]:
    """
    Returns (chosen_model, rule_name) given the request body and endpoint.
    """
    original_model = body.get("model", cfg["default_model"])
    prompt = body.get("prompt", body.get("messages", [{}])[-1].get("content", ""))
    if isinstance(prompt, list):
        # messages format: extract last user message
        for m in reversed(prompt):
            if m.get("role") == "user":
                prompt = m.get("content", "")
                break

    # Embedding endpoints always use the embedding model
    if any(endpoint.startswith(e) for e in cfg.get("embedding_endpoints", [])):
        return cfg["embedding_model"], "embedding"

    # Evaluate routes in order
    for rule in cfg.get("routes", []):
        match_type = rule.get("match", "")

        if match_type == "model_explicitly_set":
            # If the caller passed a specific model that isn't the generic default,
            # honor it without rerouting
            if original_model and original_model != cfg["default_model"]:
                target = rule.get("model") or original_model
                return target, "explicit"

        elif match_type == "prompt_length_lt":
            threshold = rule.get("value", 100)
            if isinstance(prompt, str) and len(prompt) < threshold:
                return rule["model"], rule.get("name", "length")

        elif match_type == "prompt_regex":
            pattern = rule.get("pattern", "")
            if isinstance(prompt, str) and re.search(pattern, prompt):
                return rule["model"], rule.get("name", "regex")

    return cfg["default_model"], "default"


# ── HTTP proxy ────────────────────────────────────────────────────────────────

class RouterHandler(http.server.BaseHTTPRequestHandler):
    config: dict[str, Any] = DEFAULT_CONFIG

    def log_message(self, fmt: str, *args: Any) -> None:
        pass  # silence default access log; we do our own

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length > 0 else b""

    def _forward(self, method: str, path: str, body: bytes, extra_headers: dict) -> None:
        cfg = RouterHandler.config
        upstream = cfg["ollama_url"].rstrip("/") + path

        # Parse and potentially rewrite the body
        chosen_model = None
        rule_name = "passthrough"
        rewritten = body
        original_model = None

        if body:
            try:
                parsed = json.loads(body)
                original_model = parsed.get("model")
                chosen_model, rule_name = route(parsed, path, cfg)

                if chosen_model and chosen_model != original_model:
                    parsed["model"] = chosen_model
                    rewritten = json.dumps(parsed).encode()
                    log_decision({
                        "endpoint": path,
                        "original_model": original_model,
                        "chosen_model": chosen_model,
                        "rule": rule_name,
                        "prompt_len": len(str(parsed.get("prompt", "")))
                    }, cfg)
                else:
                    chosen_model = original_model
            except (json.JSONDecodeError, KeyError):
                pass  # non-JSON body — forward as-is

        req = urllib.request.Request(
            upstream,
            data=rewritten or None,
            method=method,
        )
        req.add_header("Content-Type", "application/json")
        for k, v in extra_headers.items():
            req.add_header(k, v)

        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                # Stream the response back (handles both streaming and non-streaming)
                while True:
                    chunk = resp.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as exc:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(exc)}).encode())

    def do_POST(self) -> None:  # noqa: N802
        body = self._read_body()
        self._forward("POST", self.path, body, {})

    def do_GET(self) -> None:  # noqa: N802
        self._forward("GET", self.path, b"", {})

    def do_DELETE(self) -> None:  # noqa: N802
        body = self._read_body()
        self._forward("DELETE", self.path, body, {})


# ── Status endpoint ───────────────────────────────────────────────────────────

class RouterHandlerWithStatus(RouterHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/_router/status":
            cfg = RouterHandler.config
            status = {
                "router": "ash-model-router",
                "upstream": cfg["ollama_url"],
                "default_model": cfg["default_model"],
                "routes": len(cfg.get("routes", [])),
                "log": str(LOG_PATH),
            }
            body = json.dumps(status, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/_router/config":
            body = json.dumps(RouterHandler.config, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Ash local model router")
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--config", default=str(CONFIG_PATH))
    parser.add_argument("--print-config", action="store_true",
                        help="Print current routing config and exit")
    args = parser.parse_args()

    global CONFIG_PATH
    CONFIG_PATH = Path(args.config)
    cfg = load_config()

    if args.port:
        cfg["listen_port"] = args.port
    if args.host:
        cfg["listen_host"] = args.host

    if args.print_config:
        print(json.dumps(cfg, indent=2))
        return

    RouterHandlerWithStatus.config = cfg

    host = cfg["listen_host"]
    port = cfg["listen_port"]

    print(f"[ash-model-router] Listening on http://{host}:{port}")
    print(f"[ash-model-router] Upstream Ollama: {cfg['ollama_url']}")
    print(f"[ash-model-router] Default model: {cfg['default_model']}")
    print(f"[ash-model-router] Routes: {len(cfg.get('routes', []))}")
    print(f"[ash-model-router] Status: http://{host}:{port}/_router/status")

    server = http.server.ThreadingHTTPServer((host, port), RouterHandlerWithStatus)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[ash-model-router] Stopped.")


if __name__ == "__main__":
    main()
