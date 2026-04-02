#!/usr/bin/env bash
# uninstall.sh — clean removal of claude-code-notify hooks, config, and settings
# managed-by: claude-code-notify

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
bold "claude-code-notify — Uninstaller"
echo "─────────────────────────────────────────────"
echo ""

# ---------------------------------------------------------------------------
# Confirm before proceeding
# ---------------------------------------------------------------------------
warn "This will remove claude-code-notify hooks, config, and settings entries."
echo ""
if ! confirm "Proceed with uninstallation?" n; then
  info "Aborted — nothing was changed."
  exit 0
fi
echo ""

# ---------------------------------------------------------------------------
# Track what was removed for summary
# ---------------------------------------------------------------------------
removed_hooks=()
skipped_hooks=()
removed_conf=false
settings_cleaned=false
settings_backed_up=""

# ---------------------------------------------------------------------------
# Step 1 — Remove hook scripts from ~/.claude/hooks/
#           Only if they contain the claude-code-notify marker
# ---------------------------------------------------------------------------
info "Checking hook scripts in ${CCN_HOOKS_DIR} ..."

for hook_file in "${CCN_HOOK_FILES[@]}"; do
  target="${CCN_HOOKS_DIR}/${hook_file}"
  if [[ ! -f "$target" ]]; then
    continue
  fi
  if grep -q "claude-code-notify" "$target" 2>/dev/null; then
    rm -- "$target"
    ok "Removed ${target}"
    removed_hooks+=("$target")
  else
    warn "Skipping ${target} — does not contain 'claude-code-notify' marker"
    skipped_hooks+=("$target")
  fi
done

# Also check for notify-*.sh files that may have been copied there
for notify_script in "${CCN_HOOKS_DIR}"/notify-*.sh; do
  [[ -f "$notify_script" ]] || continue
  if grep -q "claude-code-notify" "$notify_script" 2>/dev/null; then
    rm -- "$notify_script"
    ok "Removed ${notify_script}"
    removed_hooks+=("$notify_script")
  else
    warn "Skipping ${notify_script} — does not contain 'claude-code-notify' marker"
    skipped_hooks+=("$notify_script")
  fi
done

# ---------------------------------------------------------------------------
# Step 2 — Remove config file
# ---------------------------------------------------------------------------
info "Checking config file ${CCN_CONF} ..."

if [[ -f "$CCN_CONF" ]]; then
  rm -- "$CCN_CONF"
  ok "Removed ${CCN_CONF}"
  removed_conf=true
  # Remove parent dir if now empty
  conf_dir="$(dirname "$CCN_CONF")"
  if [[ -d "$conf_dir" ]] && [[ -z "$(ls -A "$conf_dir")" ]]; then
    rmdir -- "$conf_dir"
    ok "Removed empty directory ${conf_dir}"
  fi
else
  info "Config file not found — nothing to remove."
fi

# Also check the legacy location in hooks dir
legacy_conf="${CCN_HOOKS_DIR}/claude-code-notify.conf"
if [[ -f "$legacy_conf" ]]; then
  rm -- "$legacy_conf"
  ok "Removed ${legacy_conf}"
  removed_conf=true
fi

# ---------------------------------------------------------------------------
# Step 3 — Clean settings.json
#           Remove hook entries whose "command" references our notify-*.sh
#           scripts. Backup first.
# ---------------------------------------------------------------------------
info "Checking ${CCN_SETTINGS} ..."

if [[ ! -f "$CCN_SETTINGS" ]]; then
  info "settings.json not found — nothing to clean."
else
  backup_path=$(backup_file "$CCN_SETTINGS") && settings_backed_up="$backup_path" || true
  [[ -n "$settings_backed_up" ]] && ok "Backed up settings.json → ${settings_backed_up}"

  merge_result=$(python3 -c "
import json, sys, re

settings_path = '$CCN_SETTINGS'
hooks_dir = '$CCN_HOOKS_DIR'

with open(settings_path, 'r') as f:
    data = json.load(f)

# Hook types that Claude Code supports
hook_types = ['Notification', 'Stop', 'TeammateIdle', 'PermissionRequest']
changed = False

for hook_type in hook_types:
    if hook_type not in data.get('hooks', {}):
        continue
    original = data['hooks'][hook_type]
    filtered = []
    for entry in original:
        # Navigate nested structure: entry.hooks[].command
        is_ccn = False
        if isinstance(entry, dict):
            inner_hooks = entry.get('hooks', [])
            for h in inner_hooks:
                cmd = h.get('command', '') if isinstance(h, dict) else ''
                if re.search(r'notify-[^/]*\.sh', cmd) and hooks_dir in cmd:
                    is_ccn = True
                    break
            # Also check flat structure for backwards compatibility
            if not is_ccn:
                cmd = entry.get('command', '')
                if re.search(r'notify-[^/]*\.sh', cmd) and hooks_dir in cmd:
                    is_ccn = True
        if is_ccn:
            changed = True
        else:
            filtered.append(entry)
    if filtered != original:
        data['hooks'][hook_type] = filtered
        # Clean up empty hook type
        if not filtered:
            del data['hooks'][hook_type]

# Remove empty 'hooks' key
if 'hooks' in data and not data['hooks']:
    del data['hooks']

if changed:
    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('changed')
else:
    print('unchanged')
" 2>&1)

  if [[ "$merge_result" == "changed" ]]; then
    ok "Removed claude-code-notify entries from settings.json"
    settings_cleaned=true
  elif [[ "$merge_result" == "unchanged" ]]; then
    info "No claude-code-notify entries found in settings.json"
  else
    warn "settings.json cleanup encountered an issue: ${merge_result}"
    warn "Backup is at: ${settings_backed_up}"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4 — Optionally uninstall terminal-notifier
# ---------------------------------------------------------------------------
echo ""
if has_command terminal-notifier; then
  info "terminal-notifier is installed on this system."
  warn "Note: you may use terminal-notifier for other purposes."
  if confirm "Uninstall terminal-notifier via Homebrew?" n; then
    if has_command brew; then
      brew uninstall terminal-notifier && ok "terminal-notifier uninstalled." \
        || warn "brew uninstall failed — you may need to remove it manually."
    else
      warn "Homebrew not found. Remove terminal-notifier manually if desired."
    fi
  else
    info "Skipping terminal-notifier uninstall."
  fi
else
  info "terminal-notifier not found in PATH — nothing to do."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "─────────────────────────────────────────────"
bold "Uninstall Summary"
echo ""

if [[ ${#removed_hooks[@]} -gt 0 ]]; then
  ok "Hook scripts removed (${#removed_hooks[@]}):"
  for h in "${removed_hooks[@]}"; do
    printf "    %s\n" "$h"
  done
else
  info "No hook scripts were removed."
fi

if [[ ${#skipped_hooks[@]} -gt 0 ]]; then
  warn "Hook scripts skipped (no marker, left untouched):"
  for h in "${skipped_hooks[@]}"; do
    printf "    %s\n" "$h"
  done
fi

if $removed_conf; then
  ok "Config file removed."
else
  info "Config file was not present."
fi

if $settings_cleaned; then
  ok "settings.json cleaned."
  [[ -n "$settings_backed_up" ]] && info "  Backup: ${settings_backed_up}"
else
  info "settings.json: no changes needed."
fi

echo ""
ok "claude-code-notify has been uninstalled."
echo ""
