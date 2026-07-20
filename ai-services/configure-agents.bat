@echo off
setlocal enabledelayedexpansion

set SELF_DIR=%~dp0
set SELF_DIR=%SELF_DIR:~0,-1%
for %%i in ("%SELF_DIR%\..") do set "PROJECT_ROOT=%%~fi"

set DB_PATH=%SELF_DIR%\data\memory.db
set VECTORS_PATH=%SELF_DIR%\data\vectors

set GENERATED_COUNT=0
set SKIPPED_COUNT=0
set FAILED_COUNT=0

echo === Agent Configuration Generator ===
echo Project root: %PROJECT_ROOT%
echo AI Services:  %SELF_DIR%
echo.

rem ── 1. Claude Desktop ───────────────────────────────────────
echo [1/5] Claude Desktop...
set CLAUDE_DIR=%APPDATA%\Claude
if not exist "%CLAUDE_DIR%" mkdir "%CLAUDE_DIR%"
set CLAUDE_CFG=%CLAUDE_DIR%\claude_desktop_config.json
if exist "%CLAUDE_CFG%" (
  echo   [skip] Claude Desktop config exists (manual merge required on Windows)
  set /a SKIPPED_COUNT+=1
) else (
  echo { > "%CLAUDE_CFG%"
  echo   "mcpServers": { >> "%CLAUDE_CFG%"
  echo     "codebase-memory": { >> "%CLAUDE_CFG%"
  echo       "command": "codebase-memory-mcp", >> "%CLAUDE_CFG%"
  echo       "env": { "CBM_MEMORY_PATH": "%DB_PATH%" } >> "%CLAUDE_CFG%"
  echo     } >> "%CLAUDE_CFG%"
  echo   } >> "%CLAUDE_CFG%"
  echo } >> "%CLAUDE_CFG%"
  echo   [create] Claude Desktop config created
  set /a GENERATED_COUNT+=1
)

rem ── 2. Cursor ───────────────────────────────────────────────
echo [2/5] Cursor...
set CURSOR_RULES=%PROJECT_ROOT%\.cursorrules
if exist "%CURSOR_RULES%" (
  echo   [skip] .cursorrules already exists
  set /a SKIPPED_COUNT+=1
) else (
  echo # Cursor Rules > "%CURSOR_RULES%"
  echo # DB: %DB_PATH% >> "%CURSOR_RULES%"
  echo. >> "%CURSOR_RULES%"
  echo   [create] .cursorrules created
  set /a GENERATED_COUNT+=1
)

rem ── 3. Windsurf ─────────────────────────────────────────────
echo [3/5] Windsurf...
set WINDSURF_RULES=%PROJECT_ROOT%\.windsurfrules
if exist "%WINDSURF_RULES%" (
  echo   [skip] .windsurfrules already exists
  set /a SKIPPED_COUNT+=1
) else (
  echo # Windsurf Rules > "%WINDSURF_RULES%"
  echo # DB: %DB_PATH% >> "%WINDSURF_RULES%"
  echo. >> "%WINDSURF_RULES%"
  echo   [create] .windsurfrules created
  set /a GENERATED_COUNT+=1
)

rem ── 4. Cline ────────────────────────────────────────────────
echo [4/5] Cline...
set VSCODE_DIR=%PROJECT_ROOT%\.vscode
if not exist "%VSCODE_DIR%" mkdir "%VSCODE_DIR%"
set CLINE_CFG=%VSCODE_DIR%\cline_mcp.json
if exist "%CLINE_CFG%" (
  echo   [skip] cline_mcp.json already exists
  set /a SKIPPED_COUNT+=1
) else (
  echo { > "%CLINE_CFG%"
  echo   "codebase-memory": { >> "%CLINE_CFG%"
  echo     "command": "codebase-memory-mcp", >> "%CLINE_CFG%"
  echo     "env": { "CBM_MEMORY_PATH": "%DB_PATH%" } >> "%CLINE_CFG%"
  echo   }, >> "%CLINE_CFG%"
  echo   "db-endpoint": { >> "%CLINE_CFG%"
  echo     "command": "python", >> "%CLINE_CFG%"
  echo     "args": ["%SELF_DIR%\init_db.py"] >> "%CLINE_CFG%"
  echo   } >> "%CLINE_CFG%"
  echo } >> "%CLINE_CFG%"
  echo   [create] Cline MCP config created
  set /a GENERATED_COUNT+=1
)

rem ── 5. Generic Gemini Context ────────────────────────────────
echo [5/5] Generic (Gemini)...
set GEMINI_CFG=%SELF_DIR%\gemini-context.json
if exist "%GEMINI_CFG%" (
  echo   [skip] gemini-context.json already exists
  set /a SKIPPED_COUNT+=1
) else (
  echo { > "%GEMINI_CFG%"
  echo   "system_instructions": "AI services context with codebase memory and databases.", >> "%GEMINI_CFG%"
  echo   "endpoints": { >> "%GEMINI_CFG%"
  echo     "database": { "type": "sqlite", "path": "%DB_PATH%" }, >> "%GEMINI_CFG%"
  echo     "vectors": { "type": "chromadb", "path": "%VECTORS_PATH%" } >> "%GEMINI_CFG%"
  echo   } >> "%GEMINI_CFG%"
  echo } >> "%GEMINI_CFG%"
  echo   [create] Gemini context created
  set /a GENERATED_COUNT+=1
)

echo.
echo === Summary ===
echo Generated: %GENERATED_COUNT%
echo Skipped: %SKIPPED_COUNT%
echo Failed: %FAILED_COUNT%
