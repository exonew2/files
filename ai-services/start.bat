@echo off
setlocal

set SELF_DIR=%~dp0
set VENV=%SELF_DIR%.venv

echo === Initializing databases ===
"%VENV%\Scripts\python" "%SELF_DIR%init_db.py"

echo.
echo === Starting codebase-memory MCP server ===
codebase-memory-mcp
