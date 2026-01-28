# Ctrl+L Redraw Feature

## Overview

The Ctrl+L key combination redraws the entire screen, clearing any display corruption and forcing a full re-render of the UI.

## Usage

Press **Ctrl+L** at any time while in the game window to redraw the screen.

## When to Use

### Common Scenarios

1. **Display artifacts**: When text overlaps or appears in wrong positions
2. **Terminal resize issues**: If the window was resized and the display didn't adjust properly
3. **ANSI color problems**: When colors appear incorrect or stick to wrong text
4. **General corruption**: Any time the display doesn't look right

### Example Situations

```
# Scenario 1: Text overlap after receiving a lot of data
Game sends rapid updates → Text overlaps or wraps incorrectly
Solution: Press Ctrl+L

# Scenario 2: Terminal was resized
Resize terminal window → UI doesn't adjust properly
Solution: Press Ctrl+L
```

## Implementation Details

### How It Works

1. **Key Handler**: The `event_to_msg/2` function in `Mudc.UI.App` captures Ctrl+L key press
2. **Clear Screen**: Sends ANSI escape sequences to clear the terminal
3. **State Change**: Increments a counter in the state to trigger re-render
4. **Reset Cursor**: Positions cursor at (0,0) before redraw
5. **Framework Re-render**: TermUI framework detects state change and performs full re-render

### Technical Details

```elixir
def event_to_msg(%Event.Key{key: "l"} = event, _state) do
  if Event.has_modifier?(event, :ctrl) do
    {:msg, :redraw}
  else
    {:msg, {:char, "l"}}
  end
end

def update(:redraw, state) do
  # Clear screen
  IO.write([
    IO.ANSI.clear(),
    IO.ANSI.cursor(0, 0)
  ])

  # Increment redraw counter to force a state change and trigger re-render
  {%{state | redraw_count: state.redraw_count + 1}, []}
end
```

### ANSI Escape Sequences Used

- `IO.ANSI.clear()` - Clears the entire screen
- `IO.ANSI.cursor(0, 0)` - Moves cursor to top-left corner
- `redraw_count` - Counter in state that increments to force state change
- TermUI Elm Architecture - Automatically re-renders when state changes

## Key Features

### Non-Destructive

- Preserves all state (game text, input buffer, history, etc.)
- Only affects the visual display
- No data is lost or modified (except redraw_count which is internal)

### Instant

- Executes immediately
- Full screen refresh in next render cycle (~16ms)
- No interruption to game connection or data flow

### Safe

- Can be used at any time without side effects
- Works regardless of current UI state (logs open, scrolled, etc.)
- Compatible with all other features

## Comparison with Similar Features

### Ctrl+L vs /recompile (Hot Code Reload)

- **Ctrl+L**: Visual refresh only, no code changes
- **F5**: Recompiles code and updates application logic

### Ctrl+L vs Terminal Resize

- **Ctrl+L**: Manual refresh, uses current terminal size
- **Resize**: Automatic refresh when terminal dimensions change

### Ctrl+L vs Restart

- **Ctrl+L**: Instant, preserves all state and connections
- **Restart**: Slow, loses all state and requires reconnection

## Troubleshooting

### Ctrl+L doesn't fix the issue

If pressing Ctrl+L doesn't resolve display problems:

1. **Check terminal emulator**: Some corruption is caused by the terminal itself
2. **Verify ANSI support**: Ensure your terminal supports ANSI escape sequences
3. **Try twice**: Sometimes pressing Ctrl+L twice helps with stubborn artifacts
4. **Restart as last resort**: If nothing works, exit and restart with `Mudc.run()`

### Ctrl+L doesn't respond

Make sure:
- You're in the game window (not IEx mode)
- The UI is running and active
- Your terminal captures Ctrl+L (some terminals use it for their own purposes)

### Display corruption persists

Some terminals have their own display buffers that can get corrupted independently:

1. **Terminal scroll buffer**: Clear with your terminal's scroll buffer clear command
2. **Terminal reset**: Use your terminal's reset function (often Cmd+K on macOS)
3. **Terminal emulator bug**: Consider using a different terminal emulator

## Related Features

- **/recompile**: Recompile code (may cause brief display flicker that Ctrl+L can clean up)

## Terminal Emulator Compatibility

### Known to Work Well

- **iTerm2** (macOS): Full support
- **Terminal.app** (macOS): Full support
- **Alacritty**: Full support
- **Kitty**: Full support
- **GNOME Terminal**: Full support
- **Konsole**: Full support

### May Have Issues

- **tmux**: May intercept Ctrl+L for its own purposes
- **screen**: May have similar interception
- **Some SSH clients**: May not pass Ctrl+L correctly

### Workaround for Terminal Conflicts

If your terminal or multiplexer intercepts Ctrl+L, you can:

1. **Remap the key**: Configure your terminal to pass Ctrl+L through
2. **Use alternative**: Some terminals allow remapping to Alt+L or another combination
3. **Manual redraw**: Call redraw programmatically if needed (future enhancement)

## Best Practices

### When to Use

✅ **Good use cases:**
- After switching from IEx mode
- When display looks corrupted
- Before taking screenshots
- After receiving unexpected output

❌ **Unnecessary use cases:**
- Normal operation (UI auto-refreshes)
- After every command
- As a diagnostic tool

### Performance

Ctrl+L is lightweight and can be used frequently without performance impact. However:

- Each redraw sends ~2KB of ANSI sequences to terminal
- Very rapid repeated use (multiple times per second) is unnecessary
- Normal usage (once per session or as-needed) has zero performance impact

## Future Enhancements

Potential improvements:

1. **Smart redraw**: Detect corruption and auto-redraw
2. **Partial redraw**: Redraw only corrupted regions
3. **Redraw confirmation**: Brief message confirming redraw completed
4. **Statistics**: Track redraw frequency for debugging
5. **Diagnostic mode**: Show what changed during redraw