#!/usr/bin/env bash
# ash-dep-firewall.sh — Anti-slopsquatting dependency firewall
# Wraps npm, pip, cargo installs; checks allowlists; flags typosquatting patterns.
# Item 5 of the Ash Linux hardening improvements.
#
# INSTALL:
#   sudo install -m 0755 ash-dep-firewall.sh /usr/local/bin/ash-dep-firewall
#   # Then symlink over the real tools for the agent user:
#   sudo ln -sf /usr/local/bin/ash-dep-firewall /usr/local/bin/npm
#   sudo ln -sf /usr/local/bin/ash-dep-firewall /usr/local/bin/pip
#   sudo ln -sf /usr/local/bin/ash-dep-firewall /usr/local/bin/cargo
#   # Put /usr/local/bin before /usr/bin in PATH for the agent user only.

set -euo pipefail

ALLOWLIST_DIR="/etc/ash/dep-allowlists"
AUDIT_LOG="/var/log/ash/dep-firewall.log"
mkdir -p "$(dirname "$AUDIT_LOG")"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
firewall_log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$1] $2" >> "$AUDIT_LOG"; }

###############################################################################
# Detect which real binary we are proxying
###############################################################################
SELF=$(basename "$0")
case "$SELF" in
  npm)    REAL_BIN=$(command -v -p npm  2>/dev/null || echo /usr/bin/npm)  ;;
  pip|pip3) REAL_BIN=$(command -v -p pip3 2>/dev/null || echo /usr/bin/pip3) ;;
  cargo)  REAL_BIN=$(command -v -p cargo 2>/dev/null || echo /usr/bin/cargo) ;;
  ash-dep-firewall) echo "Usage: symlink as npm, pip, or cargo"; exit 0 ;;
  *) exec "$@" ;;
esac

###############################################################################
# Extract package names from args
###############################################################################
extract_packages() {
  local tool="$1"; shift; local args=("$@")
  local pkgs=()
  case "$tool" in
    npm)
      # npm install [--save] pkg1 pkg2 ...
      local capture=false
      for a in "${args[@]}"; do
        case "$a" in
          install|i|add) capture=true ;;
          --*|-*) ;;
          *) $capture && pkgs+=("$a") ;;
        esac
      done ;;
    pip|pip3)
      # pip install pkg1 pkg2 ...
      local capture=false
      for a in "${args[@]}"; do
        case "$a" in
          install) capture=true ;;
          --*|-*) ;;
          *) $capture && pkgs+=("$a") ;;
        esac
      done ;;
    cargo)
      # cargo install pkg1 pkg2 ...
      local capture=false
      for a in "${args[@]}"; do
        case "$a" in
          install) capture=true ;;
          --*|-*) ;;
          *) $capture && pkgs+=("$a") ;;
        esac
      done ;;
  esac
  echo "${pkgs[@]:-}"
}

###############################################################################
# Typosquatting heuristics
###############################################################################

# Known popular packages per ecosystem — extend these files in production
NPM_POPULAR=( react lodash express axios moment webpack babel jest typescript )
PIP_POPULAR=( requests numpy pandas flask django scipy pillow boto3 tensorflow )
CARGO_POPULAR=( tokio serde clap rand anyhow thiserror tracing axum )

# Levenshtein distance (bash — Needleman-Wunsch approximation via Python)
levenshtein() {
  python3 -c "
a, b = '$1', '$2'
m, n = len(a), len(b)
dp = list(range(n+1))
for i in range(1, m+1):
    prev = dp[:]
    dp[0] = i
    for j in range(1, n+1):
        dp[j] = min(prev[j]+1, dp[j-1]+1, prev[j-1]+(0 if a[i-1]==b[j-1] else 1))
print(dp[n])
" 2>/dev/null || echo 99
}

check_typosquatting() {
  local pkg="$1"
  local -n popular_list="$2"
  for popular in "${popular_list[@]}"; do
    local dist
    dist=$(levenshtein "$pkg" "$popular")
    if [[ "$dist" -gt 0 && "$dist" -le 2 ]]; then
      echo "$popular (distance=$dist)"
      return 0
    fi
  done
  return 1
}

###############################################################################
# Allowlist check
###############################################################################
check_allowlist() {
  local tool="$1" pkg="$2"
  local allowlist="$ALLOWLIST_DIR/${tool}.txt"
  if [[ ! -f "$allowlist" ]]; then
    return 0  # No allowlist configured — allow but warn
  fi
  # Strip version specifiers for comparison
  local pkg_name="${pkg%%[>=<!@]*}"
  if grep -qxF "$pkg_name" "$allowlist" 2>/dev/null; then
    return 0  # On allowlist — OK
  fi
  return 1  # Not on allowlist
}

###############################################################################
# Main
###############################################################################

# If not an install command, pass through directly
FIRST_ARG="${1:-}"
case "$SELF:$FIRST_ARG" in
  npm:install|npm:i|npm:add|pip:install|pip3:install|cargo:install) ;;
  *) exec "$REAL_BIN" "$@" ;;
esac

read -ra PKGS <<< "$(extract_packages "$SELF" "$@")"

if [[ ${#PKGS[@]} -eq 0 ]]; then
  # package.json install or similar — pass through with --ignore-scripts (Item 6)
  case "$SELF" in
    npm) exec "$REAL_BIN" "$@" --ignore-scripts ;;
    *)   exec "$REAL_BIN" "$@" ;;
  esac
fi

BLOCKED=()
SUSPICIOUS=()

for pkg in "${PKGS[@]}"; do
  [[ -z "$pkg" ]] && continue

  # Check allowlist
  if ! check_allowlist "$SELF" "$pkg"; then
    firewall_log "BLOCKED" "$SELF $pkg — not in allowlist $ALLOWLIST_DIR/${SELF}.txt"
    BLOCKED+=("$pkg")
    continue
  fi

  # Typosquatting check
  case "$SELF" in
    npm)   popular_ref=NPM_POPULAR ;;
    pip*)  popular_ref=PIP_POPULAR ;;
    cargo) popular_ref=CARGO_POPULAR ;;
  esac
  match=$(check_typosquatting "$pkg" "${popular_ref}" 2>/dev/null || true)
  if [[ -n "$match" ]]; then
    echo -e "${YELLOW}[ash-dep-firewall] SUSPICIOUS: '$pkg' looks like typosquatting of '$match'${NC}" >&2
    firewall_log "SUSPICIOUS" "$SELF $pkg — possible typosquat of $match"
    SUSPICIOUS+=("$pkg (similar to $match)")
  fi
done

if [[ ${#BLOCKED[@]} -gt 0 ]]; then
  echo -e "${RED}[ash-dep-firewall] BLOCKED ${#BLOCKED[@]} package(s):${NC}" >&2
  for b in "${BLOCKED[@]}"; do echo -e "  ${RED}\u2717${NC} $b" >&2; done
  echo "" >&2
  echo "To allow, add to: $ALLOWLIST_DIR/${SELF}.txt" >&2
  exit 1
fi

if [[ ${#SUSPICIOUS[@]} -gt 0 ]]; then
  echo -e "${YELLOW}[ash-dep-firewall] Suspicious packages detected:${NC}" >&2
  for s in "${SUSPICIOUS[@]}"; do echo -e "  ${YELLOW}\u26a0${NC} $s" >&2; done
  echo -e "${YELLOW}Proceeding in 5 seconds. Ctrl-C to abort.${NC}" >&2
  sleep 5
fi

# Item 6: enforce --ignore-scripts by default for npm
case "$SELF" in
  npm)
    echo -e "${GREEN}[ash-dep-firewall] Injecting --ignore-scripts (RCE prevention)${NC}" >&2
    firewall_log "ALLOW" "npm $* --ignore-scripts"
    exec "$REAL_BIN" "$@" --ignore-scripts
    ;;
  pip|pip3)
    firewall_log "ALLOW" "$SELF $*"
    exec "$REAL_BIN" "$@" --no-build-isolation
    ;;
  cargo)
    firewall_log "ALLOW" "cargo $*"
    exec "$REAL_BIN" "$@"
    ;;
esac
