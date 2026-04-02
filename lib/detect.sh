#!/usr/bin/env bash
# lib/detect.sh — environment detection functions
# Sourced by install.sh (which already sources utils.sh first).
# All helper functions (has_command, ok, err, warn, info, confirm, CCN_SETTINGS)
# are expected to already be defined in the caller's environment.

# ---------------------------------------------------------------------------
# detect_terminal()
# Detect whether the current terminal is Terminal.app or iTerm2.
# Sets global DETECTED_TERMINAL.
# ---------------------------------------------------------------------------
detect_terminal() {
  # Prefer the $TERM_PROGRAM env var set by most macOS terminals.
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal)
      DETECTED_TERMINAL="Terminal.app"
      return 0
      ;;
    iTerm.app)
      DETECTED_TERMINAL="iTerm2"
      return 0
      ;;
  esac

  # Fallback: inspect the process tree for known terminal bundle names.
  local ppid_chain
  ppid_chain=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
  while [[ -n "$ppid_chain" && "$ppid_chain" != "1" ]]; do
    local proc_name
    proc_name=$(ps -o comm= -p "$ppid_chain" 2>/dev/null | tr -d ' ')
    case "$proc_name" in
      *Terminal*)
        DETECTED_TERMINAL="Terminal.app"
        return 0
        ;;
      *iTerm*|*iTerm2*)
        DETECTED_TERMINAL="iTerm2"
        return 0
        ;;
    esac
    ppid_chain=$(ps -o ppid= -p "$ppid_chain" 2>/dev/null | tr -d ' ')
  done

  DETECTED_TERMINAL="unknown"
}

# ---------------------------------------------------------------------------
# list_sounds()
# Print the base names (no extension) of all .aiff files in the macOS system
# sounds directory, one per line.
# ---------------------------------------------------------------------------
list_sounds() {
  local sounds_dir="/System/Library/Sounds"
  if [[ ! -d "$sounds_dir" ]]; then
    warn "System sounds directory not found: $sounds_dir"
    return 1
  fi

  for f in "$sounds_dir"/*.aiff; do
    [[ -e "$f" ]] || continue
    local base="${f##*/}"   # strip directory
    echo "${base%.aiff}"    # strip extension
  done
}

# ---------------------------------------------------------------------------
# validate_sound(name)
# Return 0 (valid) if:
#   • name is empty  → sound disabled, that is fine
#   • /System/Library/Sounds/<name>.aiff exists
# Return 1 otherwise and print an error.
# ---------------------------------------------------------------------------
validate_sound() {
  local name="${1:-}"

  # Empty string means "no sound" — treat as valid/disabled.
  if [[ -z "$name" ]]; then
    return 0
  fi

  local sound_file="/System/Library/Sounds/${name}.aiff"
  if [[ -f "$sound_file" ]]; then
    return 0
  else
    err "Sound '${name}' not found at ${sound_file}"
    info "Available sounds: $(list_sounds | tr '\n' ' ')"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# preview_sound(name)
# Play a sound non-blocking via afplay.  Empty name is silently ignored.
# ---------------------------------------------------------------------------
preview_sound() {
  local name="${1:-}"
  [[ -z "$name" ]] && return 0

  local sound_file="/System/Library/Sounds/${name}.aiff"
  if [[ ! -f "$sound_file" ]]; then
    warn "Cannot preview '${name}': file not found."
    return 1
  fi

  if ! has_command afplay; then
    warn "afplay not found; cannot preview sound."
    return 1
  fi

  afplay "$sound_file" &
}

# ---------------------------------------------------------------------------
# preflight_checks()
# Run all pre-flight checks and report results.
# Returns 0 if all required checks pass, 1 if any required check failed.
# ---------------------------------------------------------------------------
preflight_checks() {
  local all_ok=true

  # ── 1. macOS ──────────────────────────────────────────────────────────────
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ok "macOS detected ($(sw_vers -productVersion 2>/dev/null || echo 'version unknown'))"
  else
    err "macOS is required. This tool does not support $(uname -s)."
    all_ok=false
    # Non-macOS is fatal — no point continuing.
    return 1
  fi

  # ── 2. Claude Code (claude CLI) ───────────────────────────────────────────
  if has_command claude; then
    ok "Claude Code found ($(claude --version 2>/dev/null | head -1 || echo 'version unknown'))"
  else
    err "Claude Code CLI ('claude') not found in PATH."
    info "Install Claude Code: https://claude.ai/download"
    all_ok=false
  fi

  # ── 3. Homebrew ───────────────────────────────────────────────────────────
  if has_command brew; then
    ok "Homebrew found ($(brew --version 2>/dev/null | head -1))"
  else
    warn "Homebrew not found. It is needed to install terminal-notifier."
    if confirm "Install Homebrew now?"; then
      info "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if has_command brew; then
        ok "Homebrew installed successfully."
      else
        err "Homebrew installation failed. Please install manually: https://brew.sh"
        all_ok=false
      fi
    else
      warn "Skipping Homebrew installation. terminal-notifier may not be available."
    fi
  fi

  # ── 4. terminal-notifier ──────────────────────────────────────────────────
  if has_command terminal-notifier; then
    ok "terminal-notifier found ($(terminal-notifier -help 2>&1 | head -1 || echo 'version unknown'))"
  else
    warn "terminal-notifier not found. macOS notifications will not work."
    if has_command brew && confirm "Install terminal-notifier via Homebrew now?"; then
      info "Running: brew install terminal-notifier"
      brew install terminal-notifier
      if has_command terminal-notifier; then
        ok "terminal-notifier installed successfully."
      else
        err "terminal-notifier installation failed."
        info "Try manually: brew install terminal-notifier"
        all_ok=false
      fi
    else
      warn "Skipping terminal-notifier installation."
      info "To install manually: brew install terminal-notifier"
    fi
  fi

  # ── 5. python3 ────────────────────────────────────────────────────────────
  if has_command python3; then
    ok "python3 found ($(python3 --version 2>&1))"
  else
    err "python3 not found. It is required for hook scripts."
    info "Install Python 3: https://www.python.org/downloads/ or via Homebrew: brew install python3"
    all_ok=false
  fi

  # ── 6. settings.json ──────────────────────────────────────────────────────
  local settings_file="${CCN_SETTINGS:-}"
  if [[ -z "$settings_file" ]]; then
    # Derive the default path if CCN_SETTINGS is not set.
    settings_file="${HOME}/.claude/settings.json"
  fi

  if [[ -f "$settings_file" ]]; then
    ok "settings.json found at ${settings_file}"
    # Basic JSON validity check using python3 (already verified above).
    if has_command python3; then
      if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$settings_file" 2>/dev/null; then
        ok "settings.json is valid JSON"
      else
        err "settings.json exists but contains invalid JSON: ${settings_file}"
        info "Fix or recreate the file. A minimal valid file is: {}"
        all_ok=false
      fi
    fi
  else
    warn "settings.json not found at ${settings_file}"
    info "It will be created during installation."
  fi

  # ── Result ─────────────────────────────────────────────────────────────────
  if $all_ok; then
    return 0
  else
    return 1
  fi
}
