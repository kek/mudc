# F9 Toggle Feature

## Overview

The F9 key toggles between the game window and the IEx REPL, allowing you to interact with Elixir code while the MUD client is running.

## Usage

### Switching to IEx Mode

1. While in the game window, press **F9**
2. The terminal will clear and display: `=== IEx REPL Mode ===`
3. You can now use IEx normally:
   - Inspect application state
   - Call functions interactively
   - Debug issues in real-time
   - Test code changes

### Returning to Game Window

To return to the game window, call:

```elixir
Mudc.resume_ui()
```

Or use the full path:

```elixir
Mudc.UI.App.resume_ui()
```

**Tip**: If the display looks corrupted after returning, press **Ctrl+L** to redraw the screen.

## Implementation Details

### How It Works

1. **F9 Key Handler**: The `event_to_msg/2` function in `Mudc.UI.App` captures the F9 key press and sends a `:toggle_iex` message.

2. **Terminal Mode Switching**: 
   - When entering IEx mode, the app disables raw mode via `Terminal.disable_raw_mode()`
   - The screen is cleared and the cursor is shown using ANSI escape sequences
   - The terminal is restored to a normal state where IEx can accept input

3. **State Tracking**: The app state includes an `iex_mode` boolean field to track the current mode.

4. **Resuming**: 
   - The `resume_ui/0` function re-enables raw mode via `Terminal.enable_raw_mode()`
   - It sends a `:toggle_iex` message to the runtime to update the app state
   - The screen is cleared and the cursor is hidden to return to the game view

### Key Functions

- `Mudc.UI.App.event_to_msg/2` - Captures F9 key press
- `Mudc.UI.App.update/2` - Handles `:toggle_iex` message
- `Mudc.UI.App.resume_ui/0` - Public API to return to game window
- `Mudc.resume_ui/0` - Convenience wrapper in main module

### Technical Considerations

**Why Not Use F9 to Return?**

When the terminal is in IEx mode (not raw mode), the TermUI Runtime's input reader is not active, so it cannot capture F9 key presses. Therefore, we use a function call instead: `Mudc.resume_ui()`.

**ANSI Escape Sequences**

The implementation uses these ANSI escape sequences:
- `\e[?25h` - Show cursor
- `\e[?25l` - Hide cursor

These are used instead of `IO.ANSI` functions because the standard library doesn't provide cursor visibility control.

**Process Communication**

The `resume_ui/0` function uses `TermUI.Runtime.send_message/3` to communicate with the running UI process, allowing state updates without blocking the IEx shell.

## Use Cases

### Development and Debugging

- Inspect live connection state: `Mudc.Network.Connection.status()`
- Check event bus subscriptions: `Mudc.Events.Bus.subscribers(:game_text)`
- Test functions without restarting: `Mudc.send("look")`

### Interactive Exploration

- Call any module function
- Inspect process state with `:sys.get_state/1`
- Use IEx helpers like `h/1`, `i/1`, `v/1`

### Hot Code Reloading

While F5 provides recompilation within the UI, F9 allows you to:
- Test new code interactively
- Verify changes before recompiling
- Debug compilation issues

## Example Session

```elixir
# In game window, press F9
# Terminal switches to IEx mode

iex> Mudc.status()
:connected

iex> Mudc.send("score")
:ok

iex> :sys.get_state(Mudc.Network.Connection)
%{...}

# Return to game window
iex> Mudc.resume_ui()
:ok

# Back in game window, see the command results
```

## Troubleshooting

### "Error: UI runtime not found"

This means the TermUI Runtime process is not running. Make sure you started the app with `Mudc.run()`.

### Terminal appears corrupted after returning

If the terminal display is corrupted after calling `resume_ui()`, press **Ctrl+L** to redraw the screen. This will clear the display and force a full re-render without restarting the client.

Corruption can happen if:
- Terminal size changed while in IEx mode
- Multiple rapid toggles occurred
- An error occurred during mode switching

If Ctrl+L doesn't fix the issue, you may need to exit and restart with `Mudc.run()`.

### F9 doesn't respond

Make sure:
- You're in the game window (not IEx mode)
- The UI is running and active
- Your terminal emulator supports F9 key detection

## Future Enhancements

Potential improvements to this feature:

1. **Bidirectional Toggle**: Investigate ways to capture F9 in IEx mode using a separate input handler
2. **Split View**: Show both game output and IEx prompt simultaneously
3. **History Preservation**: Maintain IEx command history across toggles
4. **Visual Indicator**: Add a status bar indicator showing current mode
5. **Auto-resume**: Option to automatically return after a timeout