#!/usr/bin/env bash
# /usr/share/ash-shell/ash-shell-prompt.sh
# Starship integration — adds Ash Shell context to prompt
# Add to starship.toml:
#   [custom.ash]
#   command = "source /usr/share/ash-shell/ash-shell-prompt.sh && __ash_prompt_context"
#   when = true
#   format = "($output)"

__ash_prompt_context() {
    local info=""

    # Git info
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
        info="${branch}"
        [[ -n "$(git status --porcelain 2>/dev/null)" ]] && info+="*"
    fi

    # Dev container
    if [[ -f ".dockerignore" ]] || [[ -f "Dockerfile" ]]; then
        info="${info:+$info }🐳"
    fi

    # Dev environment
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        info="${info:+$info }venv:$(basename "$VIRTUAL_ENV")"
    fi
    if [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
        info="${info:+$info }conda:$CONDA_DEFAULT_ENV"
    fi

    [[ -n "$info" ]] && echo "$info"
}

# If called directly (not sourced with exec), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    __ash_prompt_context
fi
