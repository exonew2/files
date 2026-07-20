#!/usr/bin/env bash
set -euo pipefail

QUERY=$(wofi --dmenu --prompt "Agentic Search" --cache-file /dev/null < /dev/null 2>/dev/null) || true
[ -z "${QUERY:-}" ] && exit 0

notify-send -t 3000 -r 999 "Agentic OS" "Searching: $QUERY"

RESULTS_FILE=$(mktemp /tmp/lsfs_results.XXXXXX)
trap 'rm -f "$RESULTS_FILE"' EXIT

HAS_RESULTS=0

if command -v curl &>/dev/null; then
    OLLAMA_RESP=$(curl -s --max-time 5 -X POST http://localhost:11434/api/embeddings \
        -d "{\"model\":\"nomic-embed-text\",\"prompt\":\"${QUERY//\"/\\\"}\",\"keep_alive\":-1}" 2>/dev/null) || true
    if [ -n "$OLLAMA_RESP" ]; then
        EMBEDDING=$(echo "$OLLAMA_RESP" | tr -d '\n' | sed -n 's/.*"embedding":\(\[[^]]*\]\).*/\1/p') || true
        if [ -n "${EMBEDDING:-}" ]; then
            VECTOR=$(echo "$EMBEDDING" | tr -d ' \t\n')
            PAYLOAD="{\"vector\":$VECTOR,\"limit\":10,\"with_payload\":true}"
            QDRANT_RESP=""
            if [ -S /tmp/lsfs.sock ]; then
                QDRANT_RESP=$(curl -s --max-time 5 --unix-socket /tmp/lsfs.sock \
                    -X POST http://localhost/collections/apps/points/search \
                    -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null) || true
            fi
            if [ -z "${QDRANT_RESP:-}" ]; then
                QDRANT_RESP=$(curl -s --max-time 5 \
                    -X POST http://localhost:6333/collections/apps/points/search \
                    -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null) || true
            fi
            if [ -n "${QDRANT_RESP:-}" ]; then
                while IFS= read -r block; do
                    if echo "$block" | grep -q '"path"'; then
                        FPATH=$(echo "$block" | sed 's/.*"path":"\([^"]*\)".*/\1/')
                        FNAME=$(echo "$block" | sed 's/.*"name":"\([^"]*\)".*/\1/')
                        SCORE=$(echo "$block" | sed 's/.*"score":\([0-9.]*\).*/\1/')
                        [ -n "$FPATH" ] && echo "$FPATH | $FNAME ($SCORE)"
                    fi
                done < <(echo "$QDRANT_RESP" | tr -d '\n' | sed 's/},{/}\n{/g') > "$RESULTS_FILE"
                [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
            else
                notify-send -u critical -t 5000 "Agentic OS" "Qdrant not running. Start: systemctl start qdrant"
            fi
        fi
    else
        notify-send -u critical -t 5000 "Agentic OS" "Ollama not running. Start: systemctl start ollama"
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    PAT=$(echo "$QUERY" | grep -oiE '[0-9]+\s*(h|hr|hour|hours|d|day|days)' | head -1 | tr -d ' ') || true
    if [ -n "$PAT" ]; then
        if echo "$PAT" | grep -qiE '[0-9]+[hd]'; then
            TIME_ARG="$PAT"
        else
            NUM=$(echo "$PAT" | grep -oE '[0-9]+')
            if echo "$PAT" | grep -qiE 'h|hr|hour|hours'; then
                TIME_ARG="${NUM}h"
            else
                TIME_ARG="${NUM}d"
            fi
        fi
        if command -v fd &>/dev/null; then
            fd --changed-within "$TIME_ARG" --type f "$HOME" 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        elif command -v find &>/dev/null; then
            if echo "$TIME_ARG" | grep -q 'h$'; then
                MINS=$(( ${TIME_ARG%h} * 60 ))
            else
                MINS=$(( ${TIME_ARG%d} * 1440 ))
            fi
            find "$HOME" -mmin "-${MINS}" -type f 2>/dev/null | head -20 > "$RESULTS_FILE" || true
        fi
        [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
    fi
fi

if [ "$HAS_RESULTS" -eq 0 ] && command -v fd &>/dev/null; then
    fd --type f --max-depth 5 "$HOME" 2>/dev/null | head -15 > "$RESULTS_FILE" || true
    [ -s "$RESULTS_FILE" ] && HAS_RESULTS=1
fi

if [ "$HAS_RESULTS" -eq 0 ]; then
    notify-send -u critical -t 5000 "Agentic OS" "No files found for query"
    exit 0
fi

notify-send -t 2000 -r 999 "Agentic OS" "$(wc -l < "$RESULTS_FILE") results ready"

SELECTED=$(wofi --dmenu --prompt "Results ($(wc -l < "$RESULTS_FILE") files)" --cache-file /dev/null < "$RESULTS_FILE" 2>/dev/null) || true
[ -z "${SELECTED:-}" ] && exit 0

TARGET_PATH=$(echo "$SELECTED" | sed 's/ | .*//; s/\t.*//')
[ -z "$TARGET_PATH" ] && exit 0
[ ! -e "$TARGET_PATH" ] && notify-send -u critical -t 5000 "Agentic OS" "File not found: $TARGET_PATH" && exit 1

if [ -d "$TARGET_PATH" ]; then
    hyprctl dispatch exec "kitty -e yazi '$TARGET_PATH'"
elif echo "$TARGET_PATH" | grep -q '\.desktop$'; then
    hyprctl dispatch exec "gtk-launch '$(basename "$TARGET_PATH")'"
else
    hyprctl dispatch exec "kitty --class floating_editor -e nvim '$TARGET_PATH'"
fi
