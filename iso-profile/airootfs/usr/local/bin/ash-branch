#!/usr/bin/env bash
# ash-branch — Btrfs copy-on-write snapshot branching for Ash Linux
# Item 18: Fork, test, and merge competing AI code solutions using btrfs subvolumes.
#
# Usage:
#   ash-branch create <name>           # snapshot current $HOME into a named branch
#   ash-branch list                    # list all branches
#   ash-branch switch <name>           # switch active branch (updates symlink)
#   ash-branch diff <name>             # show files changed vs base
#   ash-branch merge <name>            # copy branch changes back to base
#   ash-branch delete <name>           # delete a branch snapshot
#   ash-branch status                  # show current branch
#
# Storage: ~/.ash/branches/<name>  (btrfs subvolume snapshots)

set -euo pipefail

BRANCHES_ROOT="${ASH_BRANCHES_ROOT:-$HOME/.ash/branches}"
BASE_DIR="${ASH_BASE_DIR:-$HOME}"
CURRENT_LINK="$BRANCHES_ROOT/.current"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[ash-branch]${NC} $*"; }
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
fail() { echo -e "  ${RED}✘${NC} $*" >&2; exit 1; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*" >&2; }

###############################################################################
# Guards
###############################################################################

require_btrfs() {
  if ! findmnt -n -o FSTYPE "$BASE_DIR" 2>/dev/null | grep -qx "btrfs"; then
    fail "ash-branch requires Btrfs filesystem at $BASE_DIR (current: $(findmnt -n -o FSTYPE "$BASE_DIR" 2>/dev/null || echo unknown))"
  fi
}

require_name() {
  local name="${1:-}"
  [[ -z "$name" ]] && fail "Branch name required"
  [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Branch name must be alphanumeric (got: $name)"
}

branch_path() { echo "$BRANCHES_ROOT/$1"; }

###############################################################################
# Commands
###############################################################################

cmd_create() {
  local name="${1:-}"
  require_name "$name"
  require_btrfs

  local dest
  dest=$(branch_path "$name")
  [[ -d "$dest" ]] && fail "Branch '$name' already exists. Delete it first: ash-branch delete $name"

  mkdir -p "$BRANCHES_ROOT"
  log "Creating branch '$name' from $BASE_DIR ..."

  if btrfs subvolume snapshot "$BASE_DIR" "$dest" 2>/dev/null; then
    ok "Branch '$name' created: $dest"
  else
    # Fallback: rsync-based snapshot for non-btrfs-root home directories
    warn "btrfs subvolume snapshot failed — falling back to rsync copy"
    mkdir -p "$dest"
    rsync -a --exclude=".ash/branches/" "$BASE_DIR/" "$dest/" \
      && ok "Branch '$name' created via rsync: $dest" \
      || fail "Failed to create branch '$name'"
  fi

  # Record metadata
  cat > "$dest/.ash-branch-meta" <<META
name=$name
created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
base=$BASE_DIR
method=btrfs-snapshot
META

  ok "Use 'ash-branch switch $name' to activate"
}

cmd_list() {
  mkdir -p "$BRANCHES_ROOT"
  local current=""
  [[ -L "$CURRENT_LINK" ]] && current=$(basename "$(readlink "$CURRENT_LINK" 2>/dev/null || echo "")")

  echo -e "\n${BOLD}Ash Branches${NC}"
  echo "────────────────────────────────"
  local found=false
  for dir in "$BRANCHES_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local bname
    bname=$(basename "$dir")
    [[ "$bname" == ".current" ]] && continue
    found=true

    local created=""
    if [[ -f "$dir/.ash-branch-meta" ]]; then
      created=$(grep '^created=' "$dir/.ash-branch-meta" | cut -d= -f2-)
    fi

    local size
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)

    if [[ "$bname" == "$current" ]]; then
      echo -e "  ${GREEN}* $bname${NC} (active)  $size  $created"
    else
      echo "    $bname  $size  $created"
    fi
  done

  $found || echo "  No branches yet. Create one: ash-branch create <name>"
  echo ""
}

cmd_switch() {
  local name="${1:-}"
  require_name "$name"
  local dest
  dest=$(branch_path "$name")
  [[ -d "$dest" ]] || fail "Branch '$name' does not exist. List branches: ash-branch list"

  ln -sfn "$dest" "$CURRENT_LINK"
  ok "Switched to branch '$name'"
  log "Branch is at: $dest"
  log "To use this branch's files, reference: $CURRENT_LINK"
}

cmd_status() {
  if [[ -L "$CURRENT_LINK" ]]; then
    local current
    current=$(basename "$(readlink "$CURRENT_LINK")")
    echo -e "${GREEN}Current branch:${NC} $current"
    echo -e "Path: $(readlink "$CURRENT_LINK")"
  else
    echo "No active branch (using base: $BASE_DIR)"
  fi
}

cmd_diff() {
  local name="${1:-}"
  require_name "$name"
  local dest
  dest=$(branch_path "$name")
  [[ -d "$dest" ]] || fail "Branch '$name' does not exist"

  log "Comparing branch '$name' vs base $BASE_DIR ..."
  # Use diff -rq to show only changed/added/removed files
  diff -rq \
    --exclude=".ash" \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude=".git" \
    --exclude="node_modules" \
    "$BASE_DIR" "$dest" 2>/dev/null || true
}

cmd_merge() {
  local name="${1:-}"
  require_name "$name"
  local dest
  dest=$(branch_path "$name")
  [[ -d "$dest" ]] || fail "Branch '$name' does not exist"

  log "Merging branch '$name' → $BASE_DIR"
  warn "This will overwrite files in $BASE_DIR that differ from the branch."
  read -rp "  Continue? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { log "Aborted."; exit 0; }

  rsync -a \
    --exclude=".ash/branches/" \
    --exclude=".ash-branch-meta" \
    "$dest/" "$BASE_DIR/" \
    && ok "Merge complete: '$name' → $BASE_DIR" \
    || fail "Merge failed"
}

cmd_delete() {
  local name="${1:-}"
  require_name "$name"
  local dest
  dest=$(branch_path "$name")
  [[ -d "$dest" ]] || fail "Branch '$name' does not exist"

  log "Deleting branch '$name' ..."

  # Remove active link if it points to this branch
  if [[ -L "$CURRENT_LINK" ]]; then
    local current
    current=$(basename "$(readlink "$CURRENT_LINK")")
    [[ "$current" == "$name" ]] && rm -f "$CURRENT_LINK"
  fi

  # Try btrfs subvolume delete first, fall back to rm
  if btrfs subvolume delete "$dest" 2>/dev/null; then
    ok "Branch '$name' deleted (btrfs subvolume)"
  else
    rm -rf "$dest"
    ok "Branch '$name' deleted"
  fi
}

###############################################################################
# Entrypoint
###############################################################################

usage() {
  cat <<'USAGE'
ash-branch — Btrfs snapshot branching for Ash Linux

Commands:
  ash-branch create <name>    Snapshot current $HOME into a named branch
  ash-branch list             List all branches
  ash-branch switch <name>    Set the active branch symlink
  ash-branch status           Show current active branch
  ash-branch diff <name>      Show files changed vs base
  ash-branch merge <name>     Copy branch changes back to base $HOME
  ash-branch delete <name>    Delete a branch

Examples:
  ash-branch create experiment-v1
  ash-branch list
  ash-branch diff experiment-v1
  ash-branch merge experiment-v1
  ash-branch delete experiment-v1

Environment:
  ASH_BRANCHES_ROOT   Branch storage dir (default: ~/.ash/branches)
  ASH_BASE_DIR        Base directory to snapshot (default: $HOME)
USAGE
}

CMD="${1:-}"
shift || true

case "$CMD" in
  create)  cmd_create "$@" ;;
  list)    cmd_list ;;
  switch)  cmd_switch "$@" ;;
  status)  cmd_status ;;
  diff)    cmd_diff "$@" ;;
  merge)   cmd_merge "$@" ;;
  delete|rm) cmd_delete "$@" ;;
  help|--help|-h) usage ;;
  "") usage; exit 1 ;;
  *) fail "Unknown command: $CMD. Run 'ash-branch help'" ;;
esac
