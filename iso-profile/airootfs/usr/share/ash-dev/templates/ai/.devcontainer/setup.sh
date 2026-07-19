#!/usr/bin/env bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
ollama pull llama3.2 2>/dev/null || true
