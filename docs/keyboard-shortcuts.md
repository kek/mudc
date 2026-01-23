# Keyboard Shortcuts Quick Reference

## Overview

This document provides a quick reference for all keyboard shortcuts available in the Mudc MUD client.

## Essential Controls

| Key | Action | Description |
|-----|--------|-------------|
| `Enter` | Send command | Sends the current input buffer to the MUD server |
| `Ctrl+C` | Quit | Exit the client immediately |
| `Ctrl+Q` | Quit | Alternative quit command |

## Directional Movement

| Key | Action | Description |
|-----|--------|-------------|
| `Ctrl+↑` | North | Send "north" command to move north |
| `Ctrl+↓` | South | Send "south" command to move south |
| `Ctrl+←` | West | Send "west" command to move west |
| `Ctrl+→` | East | Send "east" command to move east |

## Navigation & History

| Key | Action | Description |
|-----|--------|-------------|
| `↑` (Up Arrow) | Previous command | Navigate backwards through command history |
| `↓` (Down Arrow) | Next command | Navigate forwards through command history |
| `Backspace` | Delete character | Remove the last character from input buffer |

## Scrolling

| Key | Action | Description |
|-----|--------|-------------|
| `Page Up` | Scroll up | Scroll game text upward (or logs when log viewer is open) |
| `Page Down` | Scroll down | Scroll game text downward (or logs when log viewer is open) |

## Function Keys

| Key | Action | Description |
|-----|--------|-------------|
| `F5` | Recompile | Recompile code without restarting (development feature) |
| `F8` | Toggle logs | Open/close the log viewer overlay |

## Display Control

| Key | Action | Description |
|-----|--------|-------------|
| `Ctrl+L` | Redraw screen | Force a full screen refresh to fix display corruption |

## Detailed Usage

### Command History (↑/↓)

Navigate through previously entered commands:

1. Press `↑` to recall older commands
2. Press `↓` to move to newer commands
3. Press `Enter` to send the recalled command
4. Edit the command before sending if needed

**Note**: History is maintained for up to 100 commands and persists during the session.

### Scrolling (Page Up/Down)

View earlier game text or logs:

- **In game view**: Scrolls through game text buffer (up to 1000 lines)
- **In log view (F8)**: Scrolls through application logs instead
- **Auto-scroll**: Automatically returns to bottom when new text arrives (unless manually scrolled)

### F5 - Recompile

Hot reload code changes without restarting:

```elixir
# Make changes to code files
# Press F5 in the game window
# See recompilation status message
```

**Results**:
- `[Recompile successful]` - Code updated
- `[Recompile failed - check logs with F8]` - Compilation errors
- `[No changes to recompile]` - No modified files

### Ctrl+Arrow Keys - Directional Movement

Quick movement commands for MUD navigation:

- `Ctrl+Up` → Sends "north"
- `Ctrl+Down` → Sends "south"
- `Ctrl+Left` → Sends "west"
- `Ctrl+Right` → Sends "east"

**Benefits**:
- Faster than typing directional commands
- Keep hands on home row
- Combine with other movement commands (e.g., type "open door" then Ctrl+Up to go north)

**Note**: Regular arrow keys (without Ctrl) are used for command history navigation (Up/Down)

### F8 - Toggle Logs

View application logs in an overlay:

- Opens a popup showing recent log messages
- Use `Page Up`/`Page Down` to scroll logs
- Press `F8` again to close and return to game view
- Useful for debugging and viewing error messages

### Ctrl+L - Redraw Screen

Force a complete screen refresh:

- Clears the terminal display
- Re-renders the entire UI
- Preserves all state (no data loss)
- Useful after display corruption

**When to use**:
- Display shows overlapping text
- Colors appear incorrect
- Terminal was resized incorrectly



## Command-Line Commands

These are typed into the input buffer and sent with `Enter`:

| Command | Description |
|---------|-------------|
| `/connect` | Connect to the MUD server (via MMapper) |
| `/disconnect` | Disconnect from the MUD server |
| `/quit` | Exit the client (same as Ctrl+C) |

All other text is sent directly to the MUD server as game commands.

## Context-Specific Behavior

### When Log Viewer is Open (F8 pressed)

| Key | Behavior |
|-----|----------|
| `Page Up` | Scroll logs up (not game text) |
| `Page Down` | Scroll logs down (not game text) |
| `F8` | Close log viewer |





### When Command History is Active

| Key | Behavior |
|-----|----------|
| `↑` | Previous command in history |
| `↓` | Next command in history |
| Any character | Stops history navigation, switches to typing |

## Modifier Key Combinations

| Combination | Action | Description |
|-------------|--------|-------------|
| `Ctrl+C` | Quit | Exit application |
| `Ctrl+Q` | Quit | Alternative quit command |
| `Ctrl+↑` | North | Send "north" command |
| `Ctrl+↓` | South | Send "south" command |
| `Ctrl+←` | West | Send "west" command |
| `Ctrl+→` | East | Send "east" command |

**Note**: Modifier keys (Ctrl, Alt, Shift) are not used for game commands. If you need to send Ctrl+C to the game, use the appropriate game command instead.

## Status Bar Messages

The bottom status bar shows helpful hints:

**Default**:
```
Commands: /connect, /disconnect, /quit | Ctrl+Arrows: move | F5: recompile | F8: logs
```

**When connected**:
```
Connected to localhost:4242 | Commands: /disconnect, /quit
```

**When disconnected**:
```
Disconnected | Use /connect to reconnect
```

## Terminal Emulator Compatibility

### Fully Supported

Most modern terminal emulators support all shortcuts:

- iTerm2 (macOS)
- Terminal.app (macOS)
- Alacritty
- Kitty
- GNOME Terminal
- Konsole
- Windows Terminal

### Potential Conflicts

Some environments may intercept certain keys:

- **tmux/screen**: May intercept `Ctrl+L`
- **SSH clients**: May not pass function keys correctly
- **Some terminals**: May use `Ctrl+C` for copy

**Solution**: Configure your terminal/multiplexer to pass through these keys, or check the specific documentation for your setup.

## Tips & Tricks

### Efficient Command Entry

1. Use `↑` to recall recent commands instead of retyping
2. Modify recalled commands before sending
3. Build complex command sequences in history
4. Use Ctrl+Arrow keys for quick directional movement

### Display Management

1. Use `F8` to check logs when something seems wrong
2. Use `Page Up` to review game text without losing your place

### Development Workflow

1. Make code changes in your editor
2. Press `F5` to recompile without restarting
3. Press `F8` if compilation fails (check logs)



### Quick Movement

1. Use Ctrl+Arrow keys for rapid exploration
2. Combine with typed commands (e.g., "look" + Ctrl+Up)
3. Remember: plain arrows are for history, Ctrl+arrows are for movement

## Quick Reference Card

```
╔════════════════════════════════════════════════════════════╗
║                  MUDC KEYBOARD SHORTCUTS                   ║
╠════════════════════════════════════════════════════════════╣
║ Navigation                                                 ║
║   ↑/↓          Command history                            ║
║   Page Up/Down  Scroll text/logs                          ║
║   Backspace     Delete character                          ║
║                                                            ║
║ Function Keys                                              ║
║   F5           Recompile code                             ║
║   F8           Toggle log viewer                          ║
║                                                            ║
║ Control                                                    ║
║   Enter        Send command                               ║
║   Ctrl+C       Quit                                       ║
║   Ctrl+Arrows  Directional movement                      ║
║                                                            ║
║ Commands                                                   ║
║   /connect     Connect to MUD                             ║
║   /disconnect  Disconnect from MUD                        ║
║   /quit        Exit client                                ║
╚════════════════════════════════════════════════════════════╝
```

## Related Documentation

- [README.md](../README.md) - General client documentation

## Customization

Currently, keyboard shortcuts are hard-coded and cannot be customized. Future versions may include:

- Configurable key bindings
- Custom macro keys
- User-defined shortcuts
- Alternative key layouts

See the roadmap in [README.md](../README.md) for planned features.