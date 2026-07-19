#!/usr/bin/env bash
# /usr/share/ash-shell/ash-shell-init.sh
# Shell integration for bash/zsh — AI-powered context hints
# Source this from .bashrc or .zshrc:
#   source /usr/share/ash-shell/ash-shell-init.sh

ASH_SHELL_ENABLED=${ASH_SHELL_ENABLED:-1}
ASH_SHELL_LAST_DIR=""

__ash_shell_context_hint() {
    [[ "$ASH_SHELL_ENABLED" -eq 0 ]] && return
    local curr_dir="$PWD"
    [[ "$curr_dir" == "$ASH_SHELL_LAST_DIR" ]] && return
    ASH_SHELL_LAST_DIR="$curr_dir"

    local hint=""
    local git_info=""
    local recent_files=""
    local project_type=""

    # Git status
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local dirty=""
        [[ -n "$(git status --porcelain 2>/dev/null)" ]] && dirty=" ✗"
        local ahead=""
        local behind=""
        ahead=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
        behind=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)
        [[ "$ahead" -gt 0 ]] && ahead=" ↑$ahead"
        [[ "$behind" -gt 0 ]] && behind=" ↓$behind"
        git_info="${branch}${dirty}${ahead}${behind}"
    fi

    # Recent files (last 3 modified in dir)
    recent_files=$(ls -1t "$PWD" 2>/dev/null | head -3 | tr '\n' ' ')

    # Project type detection
    [[ -f "package.json" ]] && project_type="Node.js"
    [[ -f "Cargo.toml" ]] && project_type="Rust"
    [[ -f "go.mod" ]] && project_type="Go"
    [[ -f "Makefile" ]] || [[ -f "makefile" ]] && project_type="${project_type:+$project_type+}Makefile"
    [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] && project_type="${project_type:+$project_type+}Python"
    [[ -f "Gemfile" ]] && project_type="${project_type:+$project_type+}Ruby"
    [[ -f "Cargo.lock" ]] && project_type="Rust (Cargo)"
    [[ -f "composer.json" ]] && project_type="${project_type:+$project_type+}PHP"
    [[ -f "CMakeLists.txt" ]] && project_type="${project_type:+$project_type+}CMake"

    # Build hint string
    [[ -n "$project_type" ]] && hint+="[$project_type] "
    [[ -n "$git_info" ]] && hint+="⎇ $git_info "
    [[ -n "$recent_files" ]] && hint+="→ $recent_files"

    if [[ -n "$hint" ]]; then
        echo -e "\033[2m━━━ Ash Shell ─━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
        echo -e "\033[2m  $hint\033[0m"
        echo -e "\033[2m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    fi

    # Fire async AI suggestion in background (non-blocking)
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, os, subprocess, sys
from pathlib import Path

cwd = os.environ.get('PWD', '')
git_branch = '''$git_info'''
project_type = '''$project_type'''
recent_files = '''$recent_files'''

if not git_branch and not project_type:
    sys.exit(0)

prompt = (
    f'Context: cd into {cwd}\n'
    f'Project: {project_type}\n'
    f'Git: {git_branch}\n'
    f'Recent files: {recent_files}\n'
    f'Suggest the most useful next action (1 line).'
)
try:
    req = __import__('urllib.request', fromlist=['Request'])
    data = json.dumps({
        'model': 'phi3:mini', 'prompt': prompt,
        'keep_alive': -1, 'stream': False
    }).encode('utf-8')
    r = req.Request('http://localhost:11434/api/generate', data=data,
                     headers={'Content-Type': 'application/json'}, method='POST')
    with req.urlopen(r, timeout=3) as resp:
        res = json.loads(resp.read())
        suggestion = res.get('response', '').strip()
        if suggestion:
            print(f'\033[2m  \xE2\x9C\xA8 Ash suggest: {suggestion}\033[0m')
except Exception:
    pass
" 2>/dev/null &
    fi
}

# Install hooks
if [[ -n "${BASH_VERSION:-}" ]]; then
    # Bash
    __ash_shell_prompt_cmd() {
        __ash_shell_context_hint
    }
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}"'__ash_shell_prompt_cmd'
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    # Zsh
    chpwd_functions+=(__ash_shell_context_hint)
    precmd_functions+=(__ash_shell_context_hint)
fi

# Alias to toggle
ash-shell-toggle() {
    if [[ "$ASH_SHELL_ENABLED" -eq 0 ]]; then
        export ASH_SHELL_ENABLED=1
        echo "Ash Shell: enabled"
    else
        export ASH_SHELL_ENABLED=0
        echo "Ash Shell: disabled"
    fi
}
