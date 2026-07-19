#!/usr/bin/env bash
# waybar-ai-status — AI system health for Ash Waybar
set -euo pipefail

ollama_status() {
    if command -v ollama &>/dev/null; then
        local models
        if models=$(ollama list 2>/dev/null | tail -n +2 | head -c 300); then
            local count
            count=$(echo "$models" | grep -c '^' || true)
            if [ "$count" -gt 0 ]; then
                local first_model
                first_model=$(echo "$models" | head -1 | awk '{print $1}')
                echo "{\"text\":\" $first_model\",\"tooltip\":\"$count model(s) loaded\\n$(ollama list 2>/dev/null | tail -n +2 | head -5 | awk '{print $1, $3}')\",\"class\":\"ai-ok\"}"
                return
            fi
        fi
    fi
    echo "{\"text\":\" none\",\"tooltip\":\"No Ollama models loaded\",\"class\":\"ai-idle\"}"
}

qdrant_status() {
    if command -v qdrant &>/dev/null; then
        if curl -sf http://localhost:6333/health 2>/dev/null | grep -q 'ok'; then
            local count
            count=$(curl -sf http://localhost:6333/collections 2>/dev/null | jq -r '.result.collections | length' 2>/dev/null || echo 0)
            echo "{\"text\":\" $count\",\"tooltip\":\"Qdrant running\\n$count collection(s)\",\"class\":\"ai-ok\"}"
            return
        fi
    fi
    echo "{\"text\":\" down\",\"tooltip\":\"Qdrant not running\",\"class\":\"ai-down\"}"
}

lsfs_status() {
    if mountpoint -q /mnt/lsfs 2>/dev/null; then
        local count
        count=$(ls /mnt/lsfs 2>/dev/null | wc -l)
        echo "{\"text\":\" $count\",\"tooltip\":\"LSFS mounted\\n$count indexed files\",\"class\":\"ai-ok\"}"
        return
    fi
    echo "{\"text\":\" off\",\"tooltip\":\"LSFS not mounted\",\"class\":\"ai-idle\"}"
}

agent_status() {
    if pgrep -x ash-agent &>/dev/null; then
        echo "{\"text\":\"ﮧ\",\"tooltip\":\"Ash Agent running\",\"class\":\"ai-ok\"}"
        return
    fi
    echo "{\"text\":\"ﮧ\",\"tooltip\":\"Ash Agent not running\",\"class\":\"ai-idle\"}"
}

case "${1:-all}" in
    ollama) ollama_status ;;
    qdrant) qdrant_status ;;
    lsfs) lsfs_status ;;
    agent) agent_status ;;
    all)
        OLLAMA=$(ollama_status)
        QDRANT=$(qdrant_status)
        LSFS=$(lsfs_status)
        AGENT=$(agent_status)
        echo "$AGENT $OLLAMA $QDRANT $LSFS"
        ;;
esac
