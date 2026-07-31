#!/usr/bin/env bash
# ash-audit-setup.sh — Configure supply chain audit logging for Ash Linux.
# Item 20: Track all agent file edits, package installs, and network connections
#          via auditd and/or eBPF (bpftrace), producing structured JSON logs.
#
# Usage:
#   sudo bash ash-audit-setup.sh install    # install auditd rules + log rotator
#   sudo bash ash-audit-setup.sh status     # show current audit stats
#   sudo bash ash-audit-setup.sh report     # print last 50 structured events
#   sudo bash ash-audit-setup.sh uninstall  # remove audit rules

set -euo pipefail

AUDIT_RULES_FILE="/etc/audit/rules.d/99-ash-supply-chain.rules"
AUDIT_LOG="/var/log/ash/supply-chain-audit.jsonl"
REPORT_SCRIPT="/usr/local/bin/ash-audit-report"
LOGROTATE_CONF="/etc/logrotate.d/ash-audit"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[ash-audit]${NC} $*"; }
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*" >&2; }
fail() { echo -e "  ${RED}✘${NC} $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || fail "Must run as root"

CMD="${1:-install}"

###############################################################################
cmd_install() {
  log "Installing Ash supply chain audit logging..."

  # ── 1. auditd ──────────────────────────────────────────────────────────────
  if ! command -v auditctl &>/dev/null; then
    if command -v pacman &>/dev/null; then
      pacman -S --noconfirm audit
    elif command -v apt &>/dev/null; then
      DEBIAN_FRONTEND=noninteractive apt install -y auditd
    elif command -v dnf &>/dev/null; then
      dnf install -y audit
    else
      warn "auditd not found and no known package manager — skipping auditd rules"
    fi
  fi

  mkdir -p "$(dirname "$AUDIT_RULES_FILE")" /var/log/ash

  # ── 2. auditd rules ────────────────────────────────────────────────────────
  log "Writing auditd rules to $AUDIT_RULES_FILE ..."
  cat > "$AUDIT_RULES_FILE" <<'RULES'
## Ash Linux — Supply Chain Audit Rules
## Item 20: Track agent file edits, package installs, network connections

# Delete all existing rules first (clean slate)
-D

# Set buffer size large enough for busy systems
-b 16384

# Failure mode: 1 = log failures, 2 = panic on failure (use 1 for safety)
-f 1

## Package manager executions
-w /usr/bin/pacman    -p x -k ash-pkg-install
-w /usr/bin/pip3      -p x -k ash-pkg-install
-w /usr/bin/pip       -p x -k ash-pkg-install
-w /usr/bin/npm       -p x -k ash-pkg-install
-w /usr/bin/pnpm      -p x -k ash-pkg-install
-w /usr/bin/yarn      -p x -k ash-pkg-install
-w /usr/bin/cargo     -p x -k ash-pkg-install
-w /usr/local/bin/paru -p x -k ash-pkg-install

## Agent working directories — watch writes + attribute changes
-w /home/aiuser/.config/scripts -p wa -k ash-agent-file-edit
-w /home/aiuser/.local/bin      -p wa -k ash-agent-file-edit
-w /home/aiuser/projects        -p wa -k ash-agent-file-edit
-w /etc/ash                     -p wa -k ash-config-change

## Sensitive system paths — any write is suspicious
-w /etc/passwd      -p wa -k ash-system-tamper
-w /etc/shadow      -p wa -k ash-system-tamper
-w /etc/sudoers     -p wa -k ash-system-tamper
-w /etc/sudoers.d   -p wa -k ash-system-tamper
-w /etc/ssh         -p wa -k ash-system-tamper

## Binary installs — track writes to bin directories
-w /usr/local/bin -p wa -k ash-binary-install
-w /usr/bin       -p wa -k ash-binary-install

## Network connection syscalls (outbound from agent processes)
## -a always,exit -F arch=b64 -S connect -k ash-network-connect
## Note: connect is high-volume; uncomment only for deep investigation

## Privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -k ash-priv-esc
-a always,exit -F arch=b64 -S ptrace -k ash-ptrace

## Make the rules immutable for this boot (comment out during development)
## -e 2

RULES
  ok "auditd rules written"

  # ── 3. Start auditd ────────────────────────────────────────────────────────
  if command -v auditctl &>/dev/null; then
    systemctl enable --now auditd 2>/dev/null || true
    augenrules --load 2>/dev/null || auditctl -R "$AUDIT_RULES_FILE" 2>/dev/null || true
    ok "auditd started and rules loaded"
  fi

  # ── 4. Structured JSON log converter ──────────────────────────────────────
  log "Installing JSON audit log converter to $REPORT_SCRIPT ..."
  cat > "$REPORT_SCRIPT" <<'PYREPORT'
#!/usr/bin/env python3
"""
ash-audit-report — Convert auditd ausearch output to structured JSON provenance logs.
Reads from auditd and writes structured JSON to /var/log/ash/supply-chain-audit.jsonl
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

AUDIT_LOG = os.environ.get("ASH_AUDIT_LOG", "/var/log/ash/supply-chain-audit.jsonl")
KEYS_OF_INTEREST = {
    "ash-pkg-install": "package_install",
    "ash-agent-file-edit": "file_edit",
    "ash-config-change": "config_change",
    "ash-system-tamper": "system_tamper",
    "ash-binary-install": "binary_install",
    "ash-network-connect": "network_connect",
    "ash-priv-esc": "privilege_escalation",
    "ash-ptrace": "ptrace",
}

def parse_ausearch(raw: str) -> list[dict]:
    events = []
    current: dict = {}

    for line in raw.splitlines():
        if line.startswith("----"):
            if current:
                events.append(current)
            current = {}
            continue

        # Parse key=value pairs from auditd format
        # type=SYSCALL msg=audit(1234567890.123:456): arch=c000003e syscall=59 ...
        m = re.match(r"^type=(\S+)\s+msg=audit\((\d+\.\d+):(\d+)\):\s*(.*)", line)
        if m:
            event_type, ts_str, serial, rest = m.groups()
            ts = float(ts_str)
            current.setdefault("type", event_type)
            current.setdefault("ts", ts)
            current.setdefault("ts_iso", datetime.fromtimestamp(ts, tz=timezone.utc).isoformat())
            current.setdefault("serial", serial)

            # Parse key=value pairs
            for kv in re.finditer(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)', rest):
                k, v = kv.groups()
                v = v.strip('"')
                current[k] = v

    if current:
        events.append(current)
    return events


def fetch_recent(since_minutes: int = 60) -> str:
    try:
        result = subprocess.run(
            ["ausearch", "-k", ",".join(KEYS_OF_INTEREST.keys()),
             "--interpret", "--format", "raw"],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def convert_to_provenance(event: dict) -> dict | None:
    key = event.get("key", "").strip('"')
    event_class = KEYS_OF_INTEREST.get(key)
    if not event_class:
        return None

    provenance = {
        "schema": "ash-provenance-v1",
        "event_class": event_class,
        "audit_key": key,
        "ts": event.get("ts"),
        "ts_iso": event.get("ts_iso"),
        "serial": event.get("serial"),
        "pid": event.get("pid"),
        "uid": event.get("uid"),
        "auid": event.get("auid"),
        "exe": event.get("exe", "").strip('"'),
        "comm": event.get("comm", "").strip('"'),
        "syscall": event.get("syscall"),
        "path": event.get("name", event.get("path", "")),
        "cwd": event.get("cwd", ""),
        "raw": event,
    }
    return {k: v for k, v in provenance.items() if v not in (None, "", {})}


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Ash supply chain audit reporter")
    parser.add_argument("--tail", type=int, default=50, help="Show last N events")
    parser.add_argument("--write", action="store_true", help="Write events to JSONL log")
    parser.add_argument("--since", type=int, default=1440, help="Minutes to look back")
    args = parser.parse_args()

    raw = fetch_recent(args.since)
    if not raw:
        print("No audit events found (auditd may not be running or no events in window)")
        return

    events = parse_ausearch(raw)
    provenance_events = []
    for e in events:
        prov = convert_to_provenance(e)
        if prov:
            provenance_events.append(prov)

    if args.write:
        os.makedirs(os.path.dirname(AUDIT_LOG), exist_ok=True)
        with open(AUDIT_LOG, "a") as f:
            for e in provenance_events:
                f.write(json.dumps(e) + "\n")
        os.chmod(AUDIT_LOG, 0o640)
        print(f"Wrote {len(provenance_events)} events to {AUDIT_LOG}")

    recent = provenance_events[-args.tail:]
    for e in recent:
        print(json.dumps(e))

    print(f"\n--- {len(provenance_events)} provenance events found ---", file=sys.stderr)


if __name__ == "__main__":
    main()
PYREPORT
  chmod +x "$REPORT_SCRIPT"
  ok "ash-audit-report installed at $REPORT_SCRIPT"

  # ── 5. Systemd timer for periodic JSONL export ─────────────────────────────
  cat > /etc/systemd/system/ash-audit-export.service <<'SVC'
[Unit]
Description=Ash Supply Chain Audit — Export to JSONL
After=auditd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ash-audit-report --write --tail 1000
StandardOutput=journal
SVC

  cat > /etc/systemd/system/ash-audit-export.timer <<'TIMER'
[Unit]
Description=Ash Supply Chain Audit — Export every 15 minutes

[Timer]
OnBootSec=60
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
TIMER

  systemctl daemon-reload
  systemctl enable --now ash-audit-export.timer 2>/dev/null || true
  ok "Audit export timer enabled (runs every 15 min)"

  # ── 6. logrotate ───────────────────────────────────────────────────────────
  cat > "$LOGROTATE_CONF" <<'ROTATE'
/var/log/ash/supply-chain-audit.jsonl {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        systemctl reload auditd 2>/dev/null || true
    endscript
}
ROTATE
  ok "Log rotation configured: $LOGROTATE_CONF"

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  Supply Chain Audit Logging Installed            ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  Watching: package installs, agent file edits, config changes, binary installs"
  echo "  Log:      $AUDIT_LOG"
  echo "  Report:   ash-audit-report --tail 50"
  echo "  Live:     ausearch -k ash-pkg-install --interpret"
}

###############################################################################
cmd_status() {
  log "Supply Chain Audit Status"
  echo ""

  if command -v auditctl &>/dev/null; then
    echo -e "${GREEN}auditd:${NC} $(systemctl is-active auditd 2>/dev/null || echo not-running)"
    echo -e "${GREEN}Rules loaded:${NC} $(auditctl -l 2>/dev/null | grep -c 'ash-' || echo 0) ash rules"
  else
    warn "auditd not installed"
  fi

  if [[ -f "$AUDIT_LOG" ]]; then
    local count
    count=$(wc -l < "$AUDIT_LOG")
    local size
    size=$(du -sh "$AUDIT_LOG" | cut -f1)
    echo -e "${GREEN}JSONL log:${NC} $AUDIT_LOG ($count events, $size)"
    echo -e "${GREEN}Last event:${NC} $(tail -1 "$AUDIT_LOG" 2>/dev/null | python3 -c 'import json,sys; e=json.load(sys.stdin); print(e.get("ts_iso","?"), e.get("event_class","?"), e.get("exe","?"))' 2>/dev/null || echo none)"
  else
    warn "No JSONL log yet (run: ash-audit-report --write)"
  fi

  systemctl is-active --quiet ash-audit-export.timer 2>/dev/null \
    && echo -e "${GREEN}Timer:${NC} ash-audit-export.timer active" \
    || warn "ash-audit-export.timer not running"
}

###############################################################################
cmd_report() {
  if [[ -f "$REPORT_SCRIPT" ]]; then
    "$REPORT_SCRIPT" --tail "${2:-50}"
  elif [[ -f "$AUDIT_LOG" ]]; then
    tail -50 "$AUDIT_LOG"
  else
    warn "No audit data yet. Run: ash-audit-setup.sh install"
  fi
}

###############################################################################
cmd_uninstall() {
  log "Removing Ash audit rules..."
  rm -f "$AUDIT_RULES_FILE"
  systemctl stop ash-audit-export.timer ash-audit-export.service 2>/dev/null || true
  systemctl disable ash-audit-export.timer 2>/dev/null || true
  rm -f /etc/systemd/system/ash-audit-export.{service,timer}
  rm -f "$LOGROTATE_CONF"
  command -v augenrules &>/dev/null && augenrules --load 2>/dev/null || true
  systemctl daemon-reload
  ok "Audit rules removed"
}

case "$CMD" in
  install)   cmd_install ;;
  status)    cmd_status ;;
  report)    cmd_report "$@" ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "Usage: ash-audit-setup.sh [install|status|report|uninstall]"
    exit 1
    ;;
esac
