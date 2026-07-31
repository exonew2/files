# /etc/profile.d/lsfs-integration.sh
# LSFS shell integration — aliases, functions, env, and completions
# Updated: multi-collection (apps + notebooklm_context), ash-context --source flag

# ── PATH ──────────────────────────────────────────────────────────────────────
case ":${PATH}:" in
    *:"${HOME}/.local/bin":*) ;;
    *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac
case ":${PATH}:" in
    *:/usr/local/bin:*) ;;
    *) export PATH="/usr/local/bin:${PATH}" ;;
esac

# ── Environment defaults ───────────────────────────────────────────────────────
export QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
export OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/embeddings}"
export ASH_MODEL="${ASH_MODEL:-nomic-embed-text}"
export ASH_COLLECTION="${ASH_COLLECTION:-apps}"
export ASH_NB_COLLECTION="${ASH_NB_COLLECTION:-notebooklm_context}"
export NOTEBOOKLM_NOTEBOOKS="${NOTEBOOKLM_NOTEBOOKS:-18deba09-f237-4348-9ad8-68f4f6f859f7}"
export NOTEBOOKLM_CACHE_DIR="${NOTEBOOKLM_CACHE_DIR:-${HOME}/.ash/notebooklm/cache}"
export ASH_PROJECT_MCP_SCRIPT="${ASH_PROJECT_MCP_SCRIPT:-${HOME}/ash-iso/.opencode/mcp-server/server.py}"

# ── lsfs-query: multi-collection hybrid search ────────────────────────────────
# Usage: lsfs-query [--source all|local|notebooklm] [--mode hybrid|semantic|keyword] <query>
lsfs-query() {
    local script="/home/aiuser/.config/scripts/lsfs_hybrid_query.py"
    if [[ ! -f "$script" ]]; then
        script="$(python3 -c "import sys; print([p for p in sys.path if 'config/scripts' in p][0]+'/lsfs_hybrid_query.py')" 2>/dev/null)"
    fi
    if [[ -f "$script" ]]; then
        python3 "$script" "$@"
    else
        echo "lsfs-query: hybrid query script not found. Run ash-install.sh to reinstall." >&2
        return 1
    fi
}
export -f lsfs-query 2>/dev/null || true

# ── ash-context: unified context search (local + NotebookLM + project) ───────
# Usage: ash-context [query] [--source all|local|notebooklm] [--json]
ash-context() {
    local bin="${HOME}/.local/bin/ash-context"
    if [[ -x "$bin" ]]; then
        "$bin" "$@"
    else
        # Fallback to lsfs-query
        lsfs-query "$@"
    fi
}
export -f ash-context 2>/dev/null || true

# ── Convenience aliases ───────────────────────────────────────────────────────
alias lsfs='lsfs-query'
alias ash-search='lsfs-query'
alias ash-nb='lsfs-query --source notebooklm'       # search only notebooks
alias ash-local='lsfs-query --source local'          # search only local files
alias ash-all='lsfs-query --source all'              # search everything (default)

# ── Shell completions ─────────────────────────────────────────────────────────
if [ -f /usr/share/ash-shell/lsfs-completions ]; then
    . /usr/share/ash-shell/lsfs-completions
fi

# Inline basic completions for lsfs-query if completions file not present
if ! complete -p lsfs-query &>/dev/null 2>&1; then
    _lsfs_complete() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local prev="${COMP_WORDS[COMP_CWORD-1]}"
        case "$prev" in
            --source)  COMPREPLY=($(compgen -W "all local notebooklm" -- "$cur")) ;;
            --mode)    COMPREPLY=($(compgen -W "hybrid semantic keyword" -- "$cur")) ;;
            --limit)   COMPREPLY=() ;;
            *)         COMPREPLY=($(compgen -W "--source --mode --limit --json" -- "$cur")) ;;
        esac
    }
    complete -F _lsfs_complete lsfs-query lsfs ash-search ash-nb ash-local ash-all 2>/dev/null || true
fi
