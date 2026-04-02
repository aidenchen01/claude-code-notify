#!/usr/bin/env bash
# claude-code-notify — Interactive Installer
# https://github.com/anthropics/claude-code-notify
set -e

# ---------------------------------------------------------------------------
# Script directory detection & source dependencies
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

CCN_VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
USE_DEFAULTS=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install claude-code-notify — macOS notifications for Claude Code.

Options:
  --defaults    Non-interactive install with auto-detected settings
  --help, -h    Show this help message

Examples:
  ./install.sh              # Interactive install
  ./install.sh --defaults   # Auto-install with defaults (great for CI)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --defaults) USE_DEFAULTS=true; shift ;;
    --help|-h)  usage; exit 0 ;;
    *)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
printf "${BOLD}  claude-code-notify${NC} — Installer  (v%s)\n" "$CCN_VERSION"
printf "  ─────────────────────────────────────────\n"
echo ""

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
info "Running pre-flight checks..."
if ! preflight_checks; then
  err "Pre-flight checks failed. Please fix the issues above and re-run."
  exit 1
fi
ok "All pre-flight checks passed."
echo ""

# ---------------------------------------------------------------------------
# Re-install detection
# ---------------------------------------------------------------------------
EXISTING_HOOKS=()
for f in "${CCN_HOOK_FILES[@]}"; do
  if [[ -f "$CCN_HOOKS_DIR/$f" ]]; then
    EXISTING_HOOKS+=("$f")
  fi
done

if [[ ${#EXISTING_HOOKS[@]} -gt 0 ]]; then
  warn "Existing claude-code-notify hooks detected:"
  for f in "${EXISTING_HOOKS[@]}"; do
    printf "       %s\n" "$CCN_HOOKS_DIR/$f"
  done
  echo ""

  if [[ "$USE_DEFAULTS" == true ]]; then
    info "Defaults mode: overwriting existing hooks."
    REINSTALL_ACTION="overwrite"
  else
    printf "${BOLD}  How would you like to proceed?${NC}\n"
    printf "    1) Overwrite existing hooks\n"
    printf "    2) Skip already-installed hooks\n"
    printf "    3) Abort installation\n"
    while true; do
      printf "  Choice [1/2/3]: "
      read -r choice
      case "$choice" in
        1) REINSTALL_ACTION="overwrite"; break ;;
        2) REINSTALL_ACTION="skip"; break ;;
        3) info "Installation aborted."; exit 0 ;;
        *) warn "Please enter 1, 2, or 3." ;;
      esac
    done
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Interactive configuration
# ---------------------------------------------------------------------------

# — Q1: Terminal type -------------------------------------------------------
detect_terminal
DETECTED_TERM_RAW="${DETECTED_TERMINAL:-unknown}"

# Normalize detected terminal name to config value
case "$DETECTED_TERM_RAW" in
  *Terminal*|*terminal*) DETECTED_TERM="terminal" ;;
  *iTerm*|*iterm*)       DETECTED_TERM="iterm2"   ;;
  *)                     DETECTED_TERM="terminal" ;;
esac

if [[ "$USE_DEFAULTS" == true ]]; then
  CHOSEN_TERMINAL="$DETECTED_TERM"
  info "Terminal: $CHOSEN_TERMINAL (auto-detected)"
else
  printf "${BOLD}  Q1: Terminal application${NC}\n"
  printf "      Detected: ${GREEN}%s${NC} (%s)\n" "$DETECTED_TERM" "$DETECTED_TERM_RAW"
  echo ""
  printf "    1) terminal   — Apple Terminal.app\n"
  printf "    2) iterm2     — iTerm2\n"
  echo ""
  printf "  Use detected (%s)? Press Enter to accept, or type 1-2: " "$DETECTED_TERM"
  read -r term_choice

  case "$term_choice" in
    1) CHOSEN_TERMINAL="terminal" ;;
    2) CHOSEN_TERMINAL="iterm2" ;;
    "") CHOSEN_TERMINAL="$DETECTED_TERM" ;;
    *)
      warn "Invalid choice, using detected: $DETECTED_TERM"
      CHOSEN_TERMINAL="$DETECTED_TERM"
      ;;
  esac
  ok "Terminal: $CHOSEN_TERMINAL"
  echo ""
fi

# — Q2: Sounds for each event -----------------------------------------------
EVENT_NAMES=("Notification" "Stop" "Idle" "Permission")
EVENT_KEYS=("NOTIFICATION"  "STOP" "IDLE" "PERMISSION")
DEFAULT_SOUNDS=("Glass" "Hero" "Purr" "Sosumi")

declare -a CHOSEN_SOUNDS

if [[ "$USE_DEFAULTS" == true ]]; then
  CHOSEN_SOUNDS=("${DEFAULT_SOUNDS[@]}")
  info "Sounds: using defaults (Glass / Hero / Purr / Sosumi)"
else
  printf "${BOLD}  Q2: Notification sounds${NC}\n"
  printf "      Choose a sound for each event. Press Enter for the default.\n"
  echo ""

  # Get available sounds once (join with commas for display)
  AVAILABLE_SOUNDS=$(list_sounds | tr '\n' ', ' | sed 's/,$//')

  for i in "${!EVENT_NAMES[@]}"; do
    event="${EVENT_NAMES[$i]}"
    default="${DEFAULT_SOUNDS[$i]}"

    printf "    %s (default: %s)\n" "$event" "$default"
    printf "    Available: %s\n" "$AVAILABLE_SOUNDS"

    while true; do
      printf "    Sound [%s]: " "$default"
      read -r snd_choice
      snd_choice="${snd_choice:-$default}"

      # Validate the chosen sound
      if [[ -f "/System/Library/Sounds/${snd_choice}.aiff" ]]; then
        # Offer preview
        printf "    Preview? [y/N]: "
        read -r do_preview
        if [[ "${do_preview,,}" == "y" || "${do_preview,,}" == "yes" ]]; then
          preview_sound "$snd_choice"
          printf "    Keep this sound? [Y/n]: "
          read -r keep
          if [[ "${keep,,}" == "n" || "${keep,,}" == "no" ]]; then
            continue
          fi
        fi
        CHOSEN_SOUNDS+=("$snd_choice")
        break
      else
        warn "Sound '$snd_choice' not found. Please choose from the list above."
      fi
    done
    echo ""
  done
  ok "Sounds configured."
  echo ""
fi

# — Q3: Which hooks to enable -----------------------------------------------
# Events map to hook scripts:
#   Notification  -> hooks/notify-notification.sh  (settings.json: Notification)
#   Stop          -> hooks/notify-stop.sh          (settings.json: Stop)
#   TeammateIdle  -> hooks/notify-idle.sh          (settings.json: Notification — teammate idle)
#   Permission    -> hooks/notify-permission.sh    (settings.json: Notification — permission request)
HOOK_EVENTS=("Notification" "Stop" "TeammateIdle" "PermissionRequest")
HOOK_SCRIPTS=("notify-notification.sh" "notify-stop.sh" "notify-idle.sh" "notify-permission.sh")
HOOK_JSON_EVENTS=("Notification" "Stop" "TeammateIdle" "PermissionRequest")

declare -a ENABLED_HOOKS

if [[ "$USE_DEFAULTS" == true ]]; then
  ENABLED_HOOKS=(true true true true)
  info "Hooks: all events enabled"
else
  printf "${BOLD}  Q3: Which events should trigger notifications?${NC}\n"
  echo ""

  for i in "${!HOOK_EVENTS[@]}"; do
    event="${HOOK_EVENTS[$i]}"
    if confirm "    Enable $event?" y; then
      ENABLED_HOOKS+=(true)
    else
      ENABLED_HOOKS+=(false)
    fi
  done
  echo ""
fi

# — Q4: Summary & confirm ---------------------------------------------------
echo ""
printf "${BOLD}  Installation Summary${NC}\n"
printf "  ─────────────────────────────────────────\n"
printf "  Terminal:        %s\n" "$CHOSEN_TERMINAL"
printf "  Sounds:\n"
for i in "${!EVENT_NAMES[@]}"; do
  printf "    %-14s %s\n" "${EVENT_NAMES[$i]}:" "${CHOSEN_SOUNDS[$i]}"
done
printf "  Hooks:\n"
for i in "${!HOOK_EVENTS[@]}"; do
  local_enabled="${ENABLED_HOOKS[$i]}"
  if [[ "$local_enabled" == true ]]; then
    printf "    %-18s ${GREEN}enabled${NC}\n" "${HOOK_EVENTS[$i]}"
  else
    printf "    %-18s ${YELLOW}disabled${NC}\n" "${HOOK_EVENTS[$i]}"
  fi
done
printf "  Config file:     %s\n" "$CCN_HOOKS_DIR/claude-code-notify.conf"
printf "  Settings:        %s\n" "$CCN_SETTINGS"
printf "  ─────────────────────────────────────────\n"
echo ""

if [[ "$USE_DEFAULTS" != true ]]; then
  if ! confirm "  Proceed with installation?" y; then
    info "Installation cancelled."
    exit 0
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Installation — wrap in a function for rollback on failure
# ---------------------------------------------------------------------------
BACKUP_PATH=""

cleanup_on_failure() {
  err "Installation failed!"
  if [[ -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
    warn "Restoring settings.json from backup..."
    cp -- "$BACKUP_PATH" "$CCN_SETTINGS"
    ok "Backup restored: $CCN_SETTINGS"
  fi
  exit 1
}

trap cleanup_on_failure ERR

# — Step 1: Create hooks directory -------------------------------------------
mkdir -p "$CCN_HOOKS_DIR"
ok "Hooks directory: $CCN_HOOKS_DIR"

# — Step 2: Generate config file ---------------------------------------------
info "Writing configuration..."

mkdir -p "$(dirname "$CCN_HOOKS_DIR/claude-code-notify.conf")"

cat > "$CCN_HOOKS_DIR/claude-code-notify.conf" <<CONF
# claude-code-notify configuration
# Generated by install.sh on $(date +%Y-%m-%d\ %H:%M:%S)
# $CCN_MARKER

# Terminal application: terminal | iterm2
CCN_TERMINAL="$CHOSEN_TERMINAL"

# Sounds for each event (must be a name in /System/Library/Sounds/)
CCN_SOUND_NOTIFICATION="${CHOSEN_SOUNDS[0]}"
CCN_SOUND_STOP="${CHOSEN_SOUNDS[1]}"
CCN_SOUND_IDLE="${CHOSEN_SOUNDS[2]}"
CCN_SOUND_PERMISSION="${CHOSEN_SOUNDS[3]}"

# Notification titles and subtitles
CCN_TITLE="Claude Code"
CCN_SUBTITLE_NOTIFICATION="Notification"
CCN_SUBTITLE_STOP="Stop"
CCN_SUBTITLE_IDLE="Waiting"
CCN_SUBTITLE_PERMISSION="Permission"

# Default messages (edit to customize notification text)
CCN_MSG_STOP="Task completed"
CCN_MSG_IDLE="Claude is waiting for your input"
CCN_MSG_NOTIFICATION_FALLBACK="Claude has a notification"
CCN_MSG_PERMISSION="Claude needs permission to proceed"
CONF

ok "Config written: $CCN_HOOKS_DIR/claude-code-notify.conf"

# — Step 3: Copy hook scripts ------------------------------------------------
info "Installing hook scripts..."

for i in "${!HOOK_EVENTS[@]}"; do
  if [[ "${ENABLED_HOOKS[$i]}" != true ]]; then
    continue
  fi

  src_script="$SCRIPT_DIR/hooks/${HOOK_SCRIPTS[$i]}"
  dst_script="$CCN_HOOKS_DIR/${HOOK_SCRIPTS[$i]}"

  # If re-install with "skip" and file already exists, skip it
  if [[ "${REINSTALL_ACTION:-}" == "skip" && -f "$dst_script" ]]; then
    info "Skipping (already exists): ${HOOK_SCRIPTS[$i]}"
    continue
  fi

  if [[ -f "$src_script" ]]; then
    cp -- "$src_script" "$dst_script"
    chmod +x "$dst_script"
    ok "Installed: ${HOOK_SCRIPTS[$i]}"
  else
    warn "Source not found: $src_script (skipping)"
  fi
done

# — Step 4: Merge settings.json ----------------------------------------------
info "Updating Claude Code settings..."

# Ensure settings.json exists
if [[ ! -f "$CCN_SETTINGS" ]]; then
  mkdir -p "$(dirname "$CCN_SETTINGS")"
  echo '{}' > "$CCN_SETTINGS"
  info "Created new settings.json"
fi

# Backup settings.json
BACKUP_PATH=$(backup_file "$CCN_SETTINGS")
ok "Backup: $BACKUP_PATH"

# Build the list of hooks to add as JSON input for the merge script
HOOKS_JSON="["
first=true
for i in "${!HOOK_EVENTS[@]}"; do
  if [[ "${ENABLED_HOOKS[$i]}" != true ]]; then
    continue
  fi

  hook_event="${HOOK_JSON_EVENTS[$i]}"
  hook_script="$CCN_HOOKS_DIR/${HOOK_SCRIPTS[$i]}"

  if [[ "$first" == true ]]; then
    first=false
  else
    HOOKS_JSON+=","
  fi

  HOOKS_JSON+=$(printf '{"event":"%s","command":"%s","marker":"%s"}' \
    "$hook_event" "$hook_script" "$CCN_MARKER")
done
HOOKS_JSON+="]"

# Determine merge strategy: in --defaults mode, auto-append; otherwise ask
if [[ "$USE_DEFAULTS" == true ]]; then
  MERGE_STRATEGY="append"
else
  # Check if any existing hooks would conflict
  HAS_CONFLICTS=$(CCN_SETTINGS_PATH="$CCN_SETTINGS" CCN_HOOKS_JSON="$HOOKS_JSON" python3 -c "
import json, sys, os

settings_path = os.environ['CCN_SETTINGS_PATH']
hooks_json = json.loads(os.environ['CCN_HOOKS_JSON'])

with open(settings_path) as f:
    settings = json.load(f)

hooks_cfg = settings.get('hooks', {})
conflicts = []
for h in hooks_json:
    event = h['event']
    if event in hooks_cfg:
        existing = hooks_cfg[event]
        cmds = []
        if isinstance(existing, list):
            cmds = existing
        elif isinstance(existing, dict) and 'command' in existing:
            cmds = [existing]
        for entry in cmds:
            is_ccn = False
            if isinstance(entry, dict):
                for inner in entry.get('hooks', []):
                    c = inner.get('command', '') if isinstance(inner, dict) else ''
                    if 'claude-code-notify' in c:
                        is_ccn = True
                        break
                if not is_ccn:
                    c = entry.get('command', '')
                    if 'claude-code-notify' in c:
                        is_ccn = True
            if not is_ccn:
                conflicts.append(event)
                break
if conflicts:
    print(','.join(sorted(set(conflicts))))
else:
    print('')
" 2>/dev/null || echo "")

  if [[ -n "$HAS_CONFLICTS" ]]; then
    warn "Existing hooks found for events: $HAS_CONFLICTS"
    printf "${BOLD}  How should we handle existing hooks?${NC}\n"
    printf "    1) Append — add our hooks alongside existing ones\n"
    printf "    2) Replace — remove existing hooks, use ours only\n"
    printf "    3) Skip — do not modify hooks for conflicting events\n"
    while true; do
      printf "  Choice [1/2/3]: "
      read -r merge_choice
      case "$merge_choice" in
        1) MERGE_STRATEGY="append"; break ;;
        2) MERGE_STRATEGY="replace"; break ;;
        3) MERGE_STRATEGY="skip"; break ;;
        *) warn "Please enter 1, 2, or 3." ;;
      esac
    done
  else
    MERGE_STRATEGY="append"
  fi
fi

# Perform the merge using Python for reliable JSON handling
export CCN_SETTINGS_PATH="$CCN_SETTINGS"
export CCN_HOOKS_JSON="$HOOKS_JSON"
export CCN_MERGE_STRATEGY="$MERGE_STRATEGY"
export CCN_MARKER_STR="$CCN_MARKER"

python3 <<'PYEOF'
import json
import sys
import os

settings_path = os.environ['CCN_SETTINGS_PATH']
hooks_to_add = json.loads(os.environ['CCN_HOOKS_JSON'])
merge_strategy = os.environ['CCN_MERGE_STRATEGY']
marker = os.environ['CCN_MARKER_STR']

# Load current settings
with open(settings_path) as f:
    settings = json.load(f)

# Ensure "hooks" key exists
if "hooks" not in settings:
    settings["hooks"] = {}

hooks_cfg = settings["hooks"]

for hook in hooks_to_add:
    event = hook["event"]
    new_entry = {
        "hooks": [
            {
                "type": "command",
                "command": hook["command"]
            }
        ]
    }

    if event not in hooks_cfg:
        # No existing hooks for this event — just add
        hooks_cfg[event] = [new_entry]
    else:
        existing = hooks_cfg[event]

        # Normalize to list
        if isinstance(existing, dict):
            existing = [existing]
        elif not isinstance(existing, list):
            existing = []

        # Remove any previous claude-code-notify entries (avoid duplicates)
        def is_ccn_entry(e):
            if not isinstance(e, dict):
                return False
            inner = e.get("hooks", [])
            for h in inner:
                if isinstance(h, dict) and "claude-code-notify" in h.get("command", ""):
                    return True
            return False

        cleaned = [e for e in existing if not is_ccn_entry(e)]

        if merge_strategy == "replace":
            # Replace: only keep our entry
            hooks_cfg[event] = [new_entry]
        elif merge_strategy == "skip":
            # Skip: only add if there were no non-CCN hooks
            if len(cleaned) == 0:
                hooks_cfg[event] = [new_entry]
            else:
                # Keep existing + re-add ours
                cleaned.append(new_entry)
                hooks_cfg[event] = cleaned
        else:
            # Append (default): keep existing + add ours
            cleaned.append(new_entry)
            hooks_cfg[event] = cleaned

settings["hooks"] = hooks_cfg

# Write back with nice formatting
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("OK")
PYEOF

ok "Settings updated: $CCN_SETTINGS"

# — Step 5: Test notification -----------------------------------------------
echo ""
info "Sending test notification..."

if has_command terminal-notifier; then
  terminal-notifier \
    -message "claude-code-notify installed successfully!" \
    -title "Claude Code" \
    -subtitle "Test Notification" \
    -sound "${CHOSEN_SOUNDS[0]}" &>/dev/null &
  ok "Test notification sent! You should see it momentarily."
else
  warn "terminal-notifier not found — skipping test notification."
fi

# — Step 6: Final summary ----------------------------------------------------
echo ""
printf "${BOLD}  Installation complete!${NC}\n"
printf "  ─────────────────────────────────────────\n"
printf "  Config:    %s\n" "$CCN_HOOKS_DIR/claude-code-notify.conf"
printf "  Hooks in:  %s\n" "$CCN_HOOKS_DIR"
printf "  Settings:  %s\n" "$CCN_SETTINGS"
printf "  Backup:    %s\n" "${BACKUP_PATH:-none}"
echo ""
printf "  Installed hooks:\n"
for i in "${!HOOK_EVENTS[@]}"; do
  if [[ "${ENABLED_HOOKS[$i]}" == true ]]; then
    printf "    ${GREEN}✓${NC} %s → %s\n" "${HOOK_EVENTS[$i]}" "$CCN_HOOKS_DIR/${HOOK_SCRIPTS[$i]}"
  fi
done
echo ""
printf "  To edit your configuration:\n"
printf "    ${BLUE}\$EDITOR %s${NC}\n" "$CCN_HOOKS_DIR/claude-code-notify.conf"
echo ""
printf "  To uninstall:\n"
printf "    ${BLUE}./uninstall.sh${NC}\n"
echo ""

# Disable the ERR trap now that we've completed successfully
trap - ERR
