#!/usr/bin/env bash
# claude-code-notify — PermissionRequest event hook

# Drain stdin
cat > /dev/null

# Hardcoded defaults
CCN_TERMINAL="terminal"
CCN_SOUND_PERMISSION="Sosumi"
CCN_TITLE="Claude Code"
CCN_SUBTITLE_PERMISSION="Permission"
CCN_MSG_PERMISSION="Claude needs permission to proceed"

# Load user config (overrides defaults)
source "$HOME/.claude/hooks/claude-code-notify.conf" 2>/dev/null

MSG="$CCN_MSG_PERMISSION"

# Get TTY of parent process
TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')

# Validate sound file exists, build SOUND_ARG
if [ -n "$CCN_SOUND_PERMISSION" ] && [ -f "/System/Library/Sounds/${CCN_SOUND_PERMISSION}.aiff" ]; then
    SOUND_ARG=(-sound "$CCN_SOUND_PERMISSION")
else
    SOUND_ARG=()
fi

# Build ACTIVATE_CMD based on CCN_TERMINAL
if [ "$CCN_TERMINAL" = "iterm2" ]; then
    ACTIVATE_CMD='tell application "iTerm2"
    set _found to false
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s contains "'"$TTY"'" then
                    select t
                    activate
                    set _found to true
                    exit repeat
                end if
            end repeat
            if _found then exit repeat
        end repeat
        if _found then exit repeat
    end repeat
    if not _found then activate
end tell'
else
    # Default: "terminal"
    ACTIVATE_CMD='tell application "Terminal"
    set _found to false
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t contains "'"$TTY"'" then
                set index of w to 1
                set selected tab of w to t
                activate
                set _found to true
                exit repeat
            end if
        end repeat
        if _found then exit repeat
    end repeat
    if not _found then activate
end tell'
fi

# Send notification (background so hook returns quickly)
terminal-notifier \
    -message "$MSG" \
    -title "$CCN_TITLE" \
    -subtitle "$CCN_SUBTITLE_PERMISSION" \
    "${SOUND_ARG[@]}" \
    -execute "$ACTIVATE_CMD" &
