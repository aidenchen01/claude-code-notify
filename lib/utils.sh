#!/usr/bin/env bash
# lib/utils.sh — shared utility functions for claude-code-notify
# Sourced by install.sh and uninstall.sh

# ---------------------------------------------------------------------------
# Color variables — disabled when stdout is not a terminal
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'   # No Color / reset
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
  NC=''
fi

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------
info() {
  printf "${BLUE}  →${NC} %s\n" "$*"
}

ok() {
  printf "${GREEN}  ✓${NC} %s\n" "$*"
}

warn() {
  printf "${YELLOW}  ⚠${NC} %s\n" "$*" >&2
}

err() {
  printf "${RED}  ✗${NC} %s\n" "$*" >&2
}

bold() {
  printf "${BOLD}%s${NC}\n" "$*"
}

# ---------------------------------------------------------------------------
# confirm() — ask yes/no question with a configurable default
#
# Usage:
#   confirm "Proceed?" [y|n]   (default: y)
#   confirm "Are you sure?" n
#
# Returns 0 for yes, 1 for no.
# ---------------------------------------------------------------------------
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-y}"
  local reply

  if [[ "$default" == "y" || "$default" == "Y" ]]; then
    local hint="[Y/n]"
  else
    local hint="[y/N]"
  fi

  # Non-interactive: honour the default silently
  if [[ ! -t 0 ]]; then
    [[ "$default" == "y" || "$default" == "Y" ]]
    return $?
  fi

  while true; do
    printf "${BOLD}%s${NC} %s " "$prompt" "$hint"
    read -r reply
    reply="${reply:-$default}"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *)     warn "Please answer y or n." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# has_command() — check whether a command exists in PATH
#
# Usage:
#   has_command osascript && echo "available"
# ---------------------------------------------------------------------------
has_command() {
  command -v "$1" &>/dev/null
}

# ---------------------------------------------------------------------------
# backup_file() — copy a file to <path>.bak.<timestamp>
#
# Usage:
#   backup_file "$HOME/.claude/settings.json"
#
# Prints the backup path on success, returns 1 if source does not exist.
# ---------------------------------------------------------------------------
backup_file() {
  local src="$1"
  if [[ ! -f "$src" ]]; then
    return 1
  fi
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  local dest="${src}.bak.${ts}"
  cp -- "$src" "$dest"
  printf '%s\n' "$dest"
}

# ---------------------------------------------------------------------------
# Constants shared across scripts
# ---------------------------------------------------------------------------

# Marker string embedded in managed blocks so they can be identified / removed
CCN_MARKER="# managed-by: claude-code-notify"

# Directory where Claude Code hook scripts live
CCN_HOOKS_DIR="$HOME/.claude/hooks"

# Claude Code global settings file
CCN_SETTINGS="$HOME/.claude/settings.json"

# claude-code-notify runtime config (stores user preferences)
CCN_CONF="$HOME/.claude/hooks/claude-code-notify.conf"

# All hook entry-point filenames that this tool manages
CCN_HOOK_FILES=(
  "notify-notification.sh"
  "notify-stop.sh"
  "notify-idle.sh"
  "notify-permission.sh"
)
