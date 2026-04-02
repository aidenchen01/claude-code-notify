# FAQ

Frequently asked questions about claude-code-notify, organized by category.

---

## Installation Issues

### Homebrew is not installed

Homebrew is needed to install `terminal-notifier`. Install it with:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Or visit [brew.sh](https://brew.sh) for instructions. The `install.sh` script will offer to install Homebrew for you if it is missing.

### terminal-notifier install fails

If `brew install terminal-notifier` fails:

1. Update Homebrew: `brew update`
2. Try again: `brew install terminal-notifier`
3. If it still fails, check Homebrew diagnostics: `brew doctor`
4. As a last resort, you can download terminal-notifier directly from its [GitHub releases](https://github.com/julienXX/terminal-notifier/releases)

### settings.json not found

Claude Code stores its settings at `~/.claude/settings.json`. If the file does not exist:

- The installer will create it for you
- To create it manually: `echo '{}' > ~/.claude/settings.json`
- Make sure you have run Claude Code at least once, which creates the `~/.claude/` directory

### Permission denied when running install.sh

Make the script executable:

```bash
chmod +x install.sh
```

Or run it with bash directly:

```bash
bash install.sh
```

---

## Notification Not Appearing

### macOS notification permissions

macOS may block notifications from terminal-notifier. To fix:

1. Open **System Settings** > **Notifications**
2. Find **terminal-notifier** in the list
3. Make sure **Allow Notifications** is turned on
4. Set the alert style to **Alerts** or **Banners** (Banners auto-dismiss; Alerts stay until you act on them)

### Do Not Disturb / Focus mode is on

macOS Focus modes suppress notifications. Check the Control Center (top-right of the menu bar) and make sure no Focus mode is active.

### Verify terminal-notifier works

Test it directly in your terminal:

```bash
terminal-notifier -message "Hello" -title "Test"
```

If no notification appears, the issue is with terminal-notifier or macOS permissions, not with claude-code-notify.

### Check that hooks are registered

Open `~/.claude/settings.json` and verify the `hooks` section contains entries for Stop, Notification, TeammateIdle, and PermissionRequest. Each should have a `command` value pointing to the corresponding script in `~/.claude/hooks/`.

---

## Click Does Not Switch Space / Window

### Mission Control setting

For Space switching to work, macOS must allow applications to move you to the Space where their window lives. Check this setting:

1. Open **System Settings** > **Desktop & Dock** (or **Mission Control** on older macOS)
2. Make sure **"When switching to an application, switch to a Space with open windows for the application"** is **enabled**

This is the most common cause of click-not-switching-Space issues.

### Terminal type mismatch

If you use iTerm2 but your config says `CCN_TERMINAL="terminal"` (or vice versa), the AppleScript will look through the wrong application's windows and find nothing.

Check your config:

```bash
cat ~/.claude/hooks/claude-code-notify.conf | grep CCN_TERMINAL
```

Set it to match the terminal you actually use:

```bash
# For Terminal.app
CCN_TERMINAL="terminal"

# For iTerm2
CCN_TERMINAL="iterm2"
```

### Test AppleScript directly

You can test whether AppleScript can find and activate your terminal. First, find your TTY:

```bash
tty
# Example output: /dev/ttys003
```

Then run the AppleScript manually (for Terminal.app):

```bash
osascript -e 'tell application "Terminal"
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t contains "ttys003" then
        set index of w to 1
        set selected tab of w to t
        activate
        return "found"
      end if
    end repeat
  end repeat
  return "not found"
end tell'
```

If it returns "not found", the TTY may have changed or the tab may have closed.

### TTY detection issue

The hook script captures the TTY of its parent process (`$PPID`). If the process tree between Claude Code and the terminal is unusual (e.g., running through tmux, screen, or a container), the TTY may not match what the terminal application reports.

claude-code-notify is designed for direct terminal usage. tmux and screen are not currently supported.

---

## Wrong Window Focused

### Multiple Claude sessions

Each terminal tab has its own TTY. If you run multiple Claude Code sessions, each hook captures the TTY of its own tab. Notifications will correctly focus the tab that generated the event.

If you see the wrong tab being focused, check that:

1. The notification actually came from the session you expect (look at the message content)
2. You have not closed and reopened a tab (TTYs can be reassigned -- see below)

### TTY reuse after terminal restart

When you close a terminal tab and open a new one, macOS may assign the same TTY device (e.g., `/dev/ttys005`) to the new tab. This is harmless for new sessions, but a stale notification from a previous session might focus the new tab occupying that TTY.

This is rare in practice and resolves itself as new notifications replace old ones.

---

## Configuration

### How do I change the notification sound?

Edit `~/.claude/hooks/claude-code-notify.conf` and set the sound variable for the event you want to change:

```bash
CCN_SOUND_STOP="Ping"
CCN_SOUND_NOTIFICATION="Pop"
```

Available sounds are the `.aiff` files in `/System/Library/Sounds/`. List them with:

```bash
ls /System/Library/Sounds/
```

### How do I disable notifications for a specific event?

Remove or comment out the hook entry for that event in `~/.claude/settings.json`. For example, to disable TeammateIdle notifications, remove the `"TeammateIdle"` block from the `hooks` object.

### How do I disable just the sound?

Set the sound variable to an empty string:

```bash
CCN_SOUND_STOP=""
```

The notification will still appear, but without a sound.

### How do I change the notification text?

Edit `~/.claude/hooks/claude-code-notify.conf`:

```bash
CCN_TITLE="My Claude"
CCN_SUBTITLE_STOP="Finished"
CCN_MSG_STOP="All done!"
```

---

## Compatibility

### Which macOS versions are supported?

macOS 13 (Ventura) and later. The project has been tested on macOS 26. Older versions may work but are not officially supported.

### Does it work with iTerm2?

Yes. Set `CCN_TERMINAL="iterm2"` in your config. iTerm2 3.0 or later is required for the AppleScript session/TTY API used by the click-to-focus feature.

### Can it coexist with other Claude Code hooks?

Yes. Claude Code supports multiple hooks per event. The installer adds claude-code-notify entries alongside any existing hooks in `settings.json`. Other hooks are not modified or removed.

### Does it work with tmux or screen?

Not currently. tmux and screen create their own pseudo-terminals, which breaks the TTY matching between the hook script and the terminal application. If you run Claude Code inside tmux, notifications will still appear, but clicking them may not focus the correct window or pane.
