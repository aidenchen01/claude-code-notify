# claude-code-notify

macOS notifications for Claude Code that click to focus the right terminal window, even across Spaces.

<!-- TODO: Add demo GIF showing notification → click → Space switch -->
<!-- ![Demo](docs/demo.gif) -->

## Features

- **Precise window focus** via TTY matching -- clicking a notification brings you to the exact terminal tab where Claude is running, not just the application
- **Terminal.app + iTerm2 support** -- auto-detects your terminal or set it manually
- **4 hook events** -- Stop, Notification, TeammateIdle, PermissionRequest
- **Configurable sounds and messages** -- choose from any built-in macOS sound, customize titles and messages
- **One-line install** -- clone and run `./install.sh`
- **Clean uninstall** -- `./uninstall.sh` removes everything it installed

## Supported Events

| Event | Trigger | Default Sound | Default Message |
|-------|---------|---------------|-----------------|
| **Stop** | Claude finishes a task | `Hero` | "Task completed" |
| **Notification** | Claude sends a notification (reads message from stdin JSON) | `Glass` | Content of notification, or "Claude has a notification" |
| **TeammateIdle** | Claude is waiting for your input | `Purr` | "Claude is waiting for your input" |
| **PermissionRequest** | Claude needs permission to proceed | `Sosumi` | "Claude needs permission to proceed" |

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/anthropics/claude-code-notify.git
cd claude-code-notify

# 2. Run the installer
./install.sh

# 3. Start using Claude Code -- notifications just work
claude
```

## Requirements

- **macOS 13+** (Ventura or later; tested on macOS 26)
- **Claude Code** (`claude` CLI in your PATH)
- **Homebrew** (used to install terminal-notifier)
- **python3** (used by the Notification hook to parse JSON from stdin)

## How It Works

When Claude Code fires a hook event, it runs one of the shell scripts installed in `~/.claude/hooks/`. Each script:

1. **Captures the TTY** of the parent process (the terminal tab running Claude) via `$PPID`
2. **Sends a notification** using `terminal-notifier` with a `-execute` callback containing an AppleScript
3. **When you click the notification**, the AppleScript runs:
   - Iterates through all windows and tabs of your terminal application
   - Finds the one whose TTY matches the captured value
   - Brings that window to the front (`set index of w to 1`) and activates the app -- this triggers a Space switch if the window is on a different desktop

```
                          Hook fires
                              |
                              v
                    +-------------------+
                    |  Hook script runs |
                    |  captures TTY via |
                    |  ps -o tty= $PPID |
                    +-------------------+
                              |
                              v
                    +-------------------+
                    | terminal-notifier |
                    | shows macOS       |
                    | notification      |
                    +-------------------+
                              |
                         user clicks
                              |
                              v
                    +-------------------+
                    | -execute callback |
                    | runs AppleScript  |
                    +-------------------+
                              |
                              v
                    +-------------------+
                    | AppleScript loops |
                    | windows/tabs,     |
                    | matches TTY,      |
                    | set index + activate|
                    | --> Space switch   |
                    +-------------------+
```

## Configuration

All configuration lives in a single file:

```
~/.claude/hooks/claude-code-notify.conf
```

This file is sourced by every hook script. Changes take effect immediately on the next notification -- no restart required.

### Configuration Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `CCN_TERMINAL` | Terminal app: `"terminal"` or `"iterm2"` | `"terminal"` |
| `CCN_SOUND_STOP` | Sound for Stop event | `"Hero"` |
| `CCN_SOUND_NOTIFICATION` | Sound for Notification event | `"Glass"` |
| `CCN_SOUND_IDLE` | Sound for TeammateIdle event | `"Purr"` |
| `CCN_SOUND_PERMISSION` | Sound for PermissionRequest event | `"Sosumi"` |
| `CCN_TITLE` | Notification title (all events) | `"Claude Code"` |
| `CCN_SUBTITLE_STOP` | Subtitle for Stop | `"Stop"` |
| `CCN_SUBTITLE_NOTIFICATION` | Subtitle for Notification | `"Notification"` |
| `CCN_SUBTITLE_IDLE` | Subtitle for TeammateIdle | `"Waiting"` |
| `CCN_SUBTITLE_PERMISSION` | Subtitle for PermissionRequest | `"Permission"` |
| `CCN_MSG_STOP` | Message for Stop | `"Task completed"` |
| `CCN_MSG_NOTIFICATION_FALLBACK` | Fallback message for Notification (used when stdin JSON has no message) | `"Claude has a notification"` |
| `CCN_MSG_IDLE` | Message for TeammateIdle | `"Claude is waiting for your input"` |
| `CCN_MSG_PERMISSION` | Message for PermissionRequest | `"Claude needs permission to proceed"` |

### Example Configuration

```bash
# ~/.claude/hooks/claude-code-notify.conf

# Use iTerm2 instead of Terminal.app
CCN_TERMINAL="iterm2"

# Change the Stop sound
CCN_SOUND_STOP="Ping"

# Disable sound for Notification events (set to empty string)
CCN_SOUND_NOTIFICATION=""

# Custom messages
CCN_MSG_STOP="Done!"
CCN_MSG_IDLE="Hey, Claude is waiting"
```

### Listing Available Sounds

```bash
ls /System/Library/Sounds/
```

Common sounds include: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.

## Manual Installation

If you prefer to install by hand instead of using `./install.sh`:

### 1. Install terminal-notifier

```bash
brew install terminal-notifier
```

### 2. Create the configuration file

```bash
mkdir -p ~/.claude/hooks
cat > ~/.claude/hooks/claude-code-notify.conf << 'EOF'
# claude-code-notify configuration
CCN_TERMINAL="terminal"       # or "iterm2"
CCN_SOUND_STOP="Hero"
CCN_SOUND_NOTIFICATION="Glass"
CCN_SOUND_IDLE="Purr"
CCN_SOUND_PERMISSION="Sosumi"
CCN_TITLE="Claude Code"
EOF
```

### 3. Copy the hook scripts

```bash
cp hooks/notify-stop.sh        ~/.claude/hooks/notify-stop.sh
cp hooks/notify-notification.sh ~/.claude/hooks/notify-notification.sh
cp hooks/notify-idle.sh         ~/.claude/hooks/notify-idle.sh
cp hooks/notify-permission.sh   ~/.claude/hooks/notify-permission.sh
chmod +x ~/.claude/hooks/notify-*.sh
```

### 4. Register hooks in settings.json

Edit `~/.claude/settings.json` and add the hooks array:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/notify-stop.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/notify-notification.sh"
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/notify-idle.sh"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/notify-permission.sh"
          }
        ]
      }
    ]
  }
}
```

## Uninstallation

### Using the uninstaller

```bash
cd claude-code-notify
./uninstall.sh
```

### Manual removal

1. Remove hook scripts:
   ```bash
   rm -f ~/.claude/hooks/notify-stop.sh
   rm -f ~/.claude/hooks/notify-notification.sh
   rm -f ~/.claude/hooks/notify-idle.sh
   rm -f ~/.claude/hooks/notify-permission.sh
   rm -f ~/.claude/hooks/claude-code-notify.conf
   ```
2. Edit `~/.claude/settings.json` and remove the hook entries added by the installer
3. Optionally uninstall terminal-notifier:
   ```bash
   brew uninstall terminal-notifier
   ```

## Supported Terminals

### Terminal.app (default)

The default terminal on macOS. AppleScript uses `tty of tab` to match the correct tab and `set index of window to 1` to bring it to the front.

### iTerm2

Set `CCN_TERMINAL="iterm2"` in your config file. AppleScript uses `tty of session` within iTerm2's window/tab/session hierarchy. Requires iTerm2 3.0+.

### Switching terminals

Edit `~/.claude/hooks/claude-code-notify.conf`:

```bash
CCN_TERMINAL="iterm2"    # or "terminal"
```

The change takes effect on the next notification.

## Troubleshooting

See [FAQ.md](FAQ.md) for solutions to common issues, including:

- Notifications not appearing
- Clicking a notification does not switch Spaces
- Wrong window gets focused
- Installation problems

## Contributing

Contributions are welcome! Here is how to help:

1. **Fork** the repository
2. **Create a branch** for your feature or fix (`git checkout -b my-feature`)
3. **Make your changes** and test them on macOS
4. **Commit** with a clear message describing what you changed
5. **Open a Pull Request** against `main`

If you find a bug, please [open an issue](../../issues) using the provided issue template.

## License

[MIT](LICENSE)
