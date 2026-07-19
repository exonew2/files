#!/usr/bin/env bash
# swaync-ai-summarize — AI notification summarizer for swaync
# Groups similar notifications and provides summaries
set -euo pipefail

# Read notification JSON from stdin
NOTIFICATION_JSON=$(cat)

APP_NAME=$(echo "$NOTIFICATION_JSON" | jq -r '.[0].app_name // "unknown"')
SUMMARY=$(echo "$NOTIFICATION_JSON" | jq -r '.[0].summary // ""')
BODY=$(echo "$NOTIFICATION_JSON" | jq -r '.[0].body // ""')
COUNT=$(echo "$NOTIFICATION_JSON" | jq length)

# If multiple notifications from same app, group them
if [ "$COUNT" -gt 1 ]; then
    GROUPED=$(echo "$NOTIFICATION_JSON" | jq -r '[group_by(.app_name)[] | {app_name: .[0].app_name, count: length, latest_summary: .[-1].summary}]')
    echo "$GROUPED"
    exit 0
fi

# Single notification — pass through with AI enhancement if possible
if command -v ollama &>/dev/null; then
    # Only enhance if there's meaningful content
    if [ -n "$BODY" ] && [ ${#BODY} -gt 20 ]; then
        ENHANCED=$(echo "Summarize this notification: $APP_NAME: $SUMMARY — $BODY" | ollama run llama3.2:1b 2>/dev/null || echo "$NOTIFICATION_JSON")
        if [ -n "$ENHANCED" ] && [ "$ENHANCED" != "$NOTIFICATION_JSON" ]; then
            echo "$NOTIFICATION_JSON" | jq --arg enhanced "$ENHANCED" '.[0].body = $enhanced'
            exit 0
        fi
    fi
fi

echo "$NOTIFICATION_JSON"
