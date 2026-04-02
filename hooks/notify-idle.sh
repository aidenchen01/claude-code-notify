#!/usr/bin/env bash
# claude-code-notify — TeammateIdle event hook

# Drain stdin
cat > /dev/null

# Hardcoded defaults
CCN_TERMINAL="terminal"
CCN_SOUND_IDLE="Purr"
CCN_TITLE="Claude Code"
CCN_SUBTITLE_IDLE="Waiting"
CCN_MSG_IDLE="Claude is waiting for your input"

# Load user config (overrides defaults)
source "$HOME/.claude/hooks/claude-code-notify.conf" 2>/dev/null

MSG="$CCN_MSG_IDLE"

# Get TTY of parent process
TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')

# Validate sound file exists, build SOUND_ARG
if [ -n "$CCN_SOUND_IDLE" ] && [ -f "/System/Library/Sounds/${CCN_SOUND_IDLE}.aiff" ]; then
    SOUND_ARG=(-sound "$CCN_SOUND_IDLE")
else
    SOUND_ARG=()
fi

# Send notification (background so hook returns quickly)
if [ "$CCN_TERMINAL" = "iterm2" ]; then
    terminal-notifier \
        -message "$MSG" \
        -title "$CCN_TITLE" \
        -subtitle "$CCN_SUBTITLE_IDLE" \
        "${SOUND_ARG[@]}" \
        -execute "osascript -e 'tell application \"iTerm2\"
    set _found to false
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if tty of s contains \"$TTY\" then
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
end tell'" &
else
    # Default: "terminal"
    terminal-notifier \
        -message "$MSG" \
        -title "$CCN_TITLE" \
        -subtitle "$CCN_SUBTITLE_IDLE" \
        "${SOUND_ARG[@]}" \
        -execute "osascript -e 'tell application \"Terminal\"
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t contains \"$TTY\" then
                set index of w to 1
                set selected tab of w to t
                activate
                return
            end if
        end repeat
    end repeat
    activate
end tell'" &
fi
