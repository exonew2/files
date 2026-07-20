@echo off
setlocal enabledelayedexpansion

set SELF_DIR=%~dp0
set VENV=%SELF_DIR%.venv

if "%1"=="" goto help
if "%1"=="help" goto help
if "%1"=="list" goto list

if "%1"=="codebase-memory" (
  echo Starting codebase-memory-mcp MCP server...
  codebase-memory-mcp
  goto end
)

if "%1"=="notebooklm" (
  echo Starting NotebookLM CLI...
  "%VENV%\Scripts\notebooklm" %2 %3 %4 %5
  goto end
)

if "%1"=="textgrad" (
  echo Starting TextGrad...
  "%VENV%\Scripts\python" -c "from textgrad import Variable, Engine; print('TextGrad imported successfully')"
  goto end
)

echo Unknown service: %1
goto help

:list
echo Installed tools in %SELF_DIR%tools:
for /d %%d in ("%SELF_DIR%tools\*") do echo   - %%~nxd
for %%f in ("%SELF_DIR%tools\*.md") do echo   - %%~nf (skill)
echo.
echo Python packages in venv:
"%VENV%\Scripts\pip" list 2>nul | findstr /i "notebooklm textgrad" || echo   (none)
goto end

:help
echo Usage: %0 ^<service^> [args...]
echo.
echo Services:
echo   codebase-memory    Start the codebase-memory MCP server
echo   notebooklm         Run NotebookLM CLI (pass args after)
echo   textgrad           Verify TextGrad installation
echo   list               List all installed tools
echo   help               Show this help

:end
