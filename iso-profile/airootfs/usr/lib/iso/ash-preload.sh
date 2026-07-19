#!/usr/bin/bash
# /usr/lib/iso/ash-preload.sh — Preload daemon for instant app launch
# Tracks frequently used executables and preloads them into page cache.
set -euo pipefail

log() { logger -t ash-preload "$*"; }

PRELOAD_DB="/var/cache/ash-preload/usage.db"
PRELOAD_LIST="/var/cache/ash-preload/preload.list"
PRELOAD_PID="/run/ash-preload.pid"
TRACK_PID="/run/ash-preload-track.pid"
INTERVAL=300     # preload check interval (5 min)
TRACK_INTERVAL=10 # tracking scan interval (10 sec)
HISTORY_SIZE=1000
THRESHOLD=3      # min launches to trigger preload

mkdir -p /var/cache/ash-preload

usage() {
    cat <<EOF
Usage: ash-preload {start|stop|restart|status|refresh|track}

  start    Start preload daemon (loads top apps into page cache)
  stop     Stop preload daemon
  status   Show preload status
  refresh  Rebuild preload list from history and preload top apps
  track    Launch tracking daemon (logs exec events via audit or polling)
EOF
}

# Track running processes and log launches
track_launches() {
    local seen=""
    while true; do
        local current
        current=$(ps --no-headers -eo comm 2>/dev/null | sort -u || true)
        while IFS= read -r proc; do
            if [[ -n "$proc" ]]; then
                echo "$proc" >> "$PRELOAD_DB"
            fi
        done <<< "$current"
        # Keep only recent history
        tail -n "$HISTORY_SIZE" "$PRELOAD_DB" > "${PRELOAD_DB}.tmp" 2>/dev/null || true
        mv "${PRELOAD_DB}.tmp" "$PRELOAD_DB" 2>/dev/null || true
        sleep "$TRACK_INTERVAL"
    done
}

# Analyze history and build preload list
build_preload_list() {
    if [[ ! -f "$PRELOAD_DB" ]]; then
        log "No usage data yet"
        return
    fi

    sort "$PRELOAD_DB" | uniq -c | sort -rn | head -20 | while IFS= read -r line; do
        local count
        local bin
        count=$(echo "$line" | awk '{print $1}')
        bin=$(echo "$line" | awk '{print $2}')
        if [[ "$count" -ge "$THRESHOLD" ]] && command -v "$bin" &>/dev/null; then
            local path
            path=$(command -v "$bin")
            echo "$path"
        fi
    done > "$PRELOAD_LIST" 2>/dev/null || true

    local count
    count=$(wc -l < "$PRELOAD_LIST" 2>/dev/null || echo 0)
    log "Preload list built: $count entries"
}

# Preload files into page cache
do_preload() {
    if [[ ! -f "$PRELOAD_LIST" ]]; then
        log "No preload list found — running build"
        build_preload_list
    fi

    if [[ ! -f "$PRELOAD_LIST" ]]; then
        return
    fi

    local total=0
    while IFS= read -r path; do
        if [[ -f "$path" ]] && [[ -r "$path" ]]; then
            # Read file into page cache (vmtouch / finch style)
            dd if="$path" of=/dev/null bs=4K count=1 2>/dev/null || true
            total=$((total + 1))
        fi
    done < "$PRELOAD_LIST"

    # Also preload common shared libraries
    for lib in libc.so.6 libm.so.6 libpthread.so.0 libglib-2.0.so.0 libgdk_pixbuf-2.0.so.0 libwayland-client.so.0; do
        local libpath
        libpath=$(ldconfig -p 2>/dev/null | grep -m1 "$lib" | awk '{print $NF}' || true)
        if [[ -n "$libpath" ]] && [[ -f "$libpath" ]]; then
            dd if="$libpath" of=/dev/null bs=4K count=1 2>/dev/null || true
        fi
    done

    log "Preloaded $total binaries into page cache"
}

start_daemon() {
    if [[ -f "$PRELOAD_PID" ]] && kill -0 "$(cat "$PRELOAD_PID")" 2>/dev/null; then
        log "Already running (pid $(cat "$PRELOAD_PID"))"
        exit 0
    fi

    # Start tracking daemon
    track_launches &
    echo $! > "$TRACK_PID"

    # Preload once at start
    do_preload

    # Main loop: periodically rebuild and preload
    (
        while true; do
            sleep "$INTERVAL"
            build_preload_list
            do_preload
        done
    ) &
    echo $! > "$PRELOAD_PID"
    log "ash-preload daemon started (pid $(cat "$PRELOAD_PID"))"
}

stop_daemon() {
    if [[ -f "$PRELOAD_PID" ]]; then
        kill "$(cat "$PRELOAD_PID")" 2>/dev/null || true
        rm -f "$PRELOAD_PID"
    fi
    if [[ -f "$TRACK_PID" ]]; then
        kill "$(cat "$TRACK_PID")" 2>/dev/null || true
        rm -f "$TRACK_PID"
    fi
    log "ash-preload daemon stopped"
}

case "${1:-start}" in
    start)   start_daemon ;;
    stop)    stop_daemon ;;
    restart) stop_daemon; start_daemon ;;
    refresh) build_preload_list; do_preload ;;
    track)   track_launches ;;
    status)
        if [[ -f "$PRELOAD_PID" ]] && kill -0 "$(cat "$PRELOAD_PID")" 2>/dev/null; then
            echo "ash-preload: running (pid $(cat "$PRELOAD_PID"))"
            echo "Preload list: $(wc -l < "$PRELOAD_LIST" 2>/dev/null || echo 0) entries"
            echo "History: $(wc -l < "$PRELOAD_DB" 2>/dev/null || echo 0) entries"
        else
            echo "ash-preload: not running"
        fi
        ;;
    *)       usage; exit 1 ;;
esac
