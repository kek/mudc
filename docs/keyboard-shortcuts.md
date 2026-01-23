# Keyboard Shortcuts Quick Reference

## Overview

This document provides a quick reference for all keyboard shortcuts available in the Mudc MUD client.

## Essential Controls

| Key | Action | Description |
|-----|--------|-------------|
| `Enter` | Send command | Sends the current input buffer to the MUD server |
| `Ctrl+C` | Quit | Exit the client immediately |
| `Ctrl+Q` | Quit | Alternative quit command |

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
| `F9` | Toggle IEx | Switch between game window and IEx REPL |

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

### F8 - Toggle Logs

View application logs in an overlay:

- Opens a popup showing recent log messages
- Use `Page Up`/`Page Down` to scroll logs
- Press `F8` again to close and return to game view
- Useful for debugging and viewing error messages

### F9 - Toggle IEx

Switch between game window and IEx REPL:

**Entering IEx mode**:
1. Press `F9` in game window
2. Terminal switches to normal mode
3. IEx prompt becomes available
4. Game remains connected in background

**Returning to game**:
```elixir
Mudc.resume_ui()
```

See [f9-toggle.md](f9-toggle.md) for detailed documentation.

### Ctrl+L - Redraw Screen

Force a complete screen refresh:

- Clears the terminal display
- Re-renders the entire UI
- Preserves all state (no data loss)
- Useful after display corruption

**When to use**:
- After returning from IEx mode (F9)
- Display shows overlapping text
- Colors appear incorrect
- Terminal was resized incorrectly

See [ctrl-l-redraw.md](ctrl-l-redraw.md) for detailed documentation.

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

### When in IEx Mode (F9 pressed)

| Key | Behavior |
|-----|----------|
| All keys | Normal IEx behavior (terminal in normal mode) |
| `F9` | Not available (call `Mudc.resume_ui()` instead) |

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
| `Ctrl+L` | Redraw | Force screen refresh |

**Note**: Modifier keys (Ctrl, Alt, Shift) are not used for game commands. If you need to send Ctrl+C to the game, use the appropriate game command instead.

## Status Bar Messages

The bottom status bar shows helpful hints:

**Default**:
```
Commands: /connect, /disconnect, /quit | F5: recompile | F8: logs | F9: IEx | Ctrl+L: redraw
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

### Display Management

1. Press `Ctrl+L` after switching from IEx (F9) for clean display
2. Use `F8` to check logs when something seems wrong
3. Use `Page Up` to review game text without losing your place

### Development Workflow

1. Make code changes in your editor
2. Press `F5` to recompile without restarting
3. Press `F8` if compilation fails (check logs)
4. Press `F9` to debug interactively with IEx
5. Call `Mudc.resume_ui()` to return
6. Press `Ctrl+L` if display looks wrong

### Recovering from Display Issues

1. First try: `Ctrl+L` (redraw)
2. If that fails: `F9` → `Mudc.resume_ui()` (mode toggle)
3. Last resort: `Ctrl+C` (quit) and restart

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
║   F9           Toggle IEx REPL                            ║
║                                                            ║
║ Control                                                    ║
║   Enter        Send command                               ║
║   Ctrl+C       Quit                                       ║
║   Ctrl+L       Redraw screen                              ║
║                                                            ║
║ Commands                                                   ║
║   /connect     Connect to MUD                             ║
║   /disconnect  Disconnect from MUD                        ║
║   /quit        Exit client                                ║
╚════════════════════════════════════════════════════════════╝
```

## Related Documentation

- [F9 Toggle Feature](f9-toggle.md) - Detailed IEx REPL documentation
- [Ctrl+L Redraw Feature](ctrl-l-redraw.md) - Screen refresh documentation
- [README.md](../README.md) - General client documentation

## Customization

Currently, keyboard shortcuts are hard-coded and cannot be customized. Future versions may include:

- Configurable key bindings
- Custom macro keys
- User-defined shortcuts
- Alternative key layouts

See the roadmap in [README.md](../README.md) for planned features.