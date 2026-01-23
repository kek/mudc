# Manual Testing Guide for Ctrl+L Redraw Feature

## Overview

This guide provides steps to manually test the Ctrl+L screen redraw functionality.

## Prerequisites

1. MMapper running on `localhost:4242` (or configure connection)
2. Mudc client compiled: `mix compile`
3. Terminal emulator that supports ANSI escape codes

## Test Scenarios

### Test 1: Basic Redraw

**Purpose**: Verify Ctrl+L clears and redraws the screen

**Steps**:
1. Start the client: `iex -S mix`
2. Run: `Mudc.run()`
3. Type some commands and see output
4. Press `Ctrl+L`

**Expected Result**:
- Screen clears completely
- Full UI redraws immediately
- All content (header, vitals, game text, input, status) appears correctly
- No visual artifacts or corruption

### Test 2: Redraw While Scrolled

**Purpose**: Verify scroll position is maintained

**Steps**:
1. Start client and get some game output (20+ lines)
2. Press `Page Up` to scroll up
3. Press `Ctrl+L`

**Expected Result**:
- Screen clears and redraws
- Scroll position is maintained (not auto-scrolled to bottom)
- Scrolled content is visible and correct

### Test 4: Redraw with Log Viewer Open

**Purpose**: Verify redraw works with overlays

**Steps**:
1. Start client
2. Press `F8` to open log viewer
3. Press `Ctrl+L`

**Expected Result**:
- Screen clears and redraws
- Log viewer overlay reappears correctly
- Logs are visible and properly formatted
- Border and header intact

### Test 5: Multiple Rapid Redraws

**Purpose**: Verify stability with repeated use

**Steps**:
1. Start client
2. Press `Ctrl+L` 5 times rapidly
3. Wait 1 second
4. Verify display

**Expected Result**:
- No crashes or errors
- Final display is clean and correct
- No performance degradation
- No memory leaks (check with `:observer.start()`)

### Test 6: Redraw During Active Connection

**Purpose**: Verify no interruption to game connection

**Steps**:
1. Start client and connect: `/connect`
2. Send game command: `look`
3. While receiving output, press `Ctrl+L`
4. Send another command: `score`

**Expected Result**:
- Redraw happens immediately
- No connection interruption
- All game output received and displayed
- Commands continue to work normally

### Test 7: Redraw with Long Input Buffer

**Purpose**: Verify input is preserved

**Steps**:
1. Start client
2. Type a long command (50+ characters) but don't send it
3. Press `Ctrl+L`

**Expected Result**:
- Screen clears and redraws
- Input buffer is preserved exactly
- Cursor position in input is correct
- Can continue typing or send command

### Test 8: Redraw After Window Resize

**Purpose**: Verify interaction with resize events

**Steps**:
1. Start client
2. Resize terminal window (make smaller, then larger)
3. Press `Ctrl+L`

**Expected Result**:
- Screen clears and redraws at current terminal size
- UI elements fit properly in new dimensions
- No overlap or cut-off content
- Viewport adjusts correctly

## Known Issues to Watch For

### Issue: Clear Without Redraw
**Symptom**: Screen clears but stays blank
**Cause**: `force_render` not called or Runtime not found
**Verification**: Check logs with F8

### Issue: Partial Redraw
**Symptom**: Only some UI elements redraw
**Cause**: State corruption or render tree issues
**Verification**: Check all UI components render correctly

### Issue: Flicker
**Symptom**: Screen flickers or shows artifacts briefly
**Cause**: Timing issue between clear and redraw
**Verification**: Adjust `Process.sleep(10)` duration

### Issue: No Response
**Symptom**: Ctrl+L does nothing
**Cause**: Terminal intercepts Ctrl+L or key not captured
**Verification**: Try in different terminal emulator

## Debugging Commands

If issues occur during testing:

```elixir
# Check if Runtime is running
Process.whereis(TermUI.Runtime)

# Check app state
:sys.get_state(TermUI.Runtime)

# View logs
# Press F8 or:
Mudc.UI.LogBuffer.get_logs()

# Force manual redraw
TermUI.Runtime.force_render(Process.whereis(TermUI.Runtime))

# Check terminal size
TermUI.Terminal.get_terminal_size()

# Verify state change on redraw
# Start an IEx session with: iex -S mix
iex> pid = Process.whereis(Mudc.UI.App)
# If not found, you need to get the runtime's root component PID differently

# Check redraw_count before Ctrl+L
# Press Ctrl+L
# Check state again and redraw_count should have incremented
```

## Performance Testing

### Memory Usage

```elixir
# Start observer
:observer.start()

# Navigate to Applications tab
# Find :mudc application
# Monitor memory while pressing Ctrl+L repeatedly
```

**Expected**: No memory growth, stable usage

### Render Performance

```elixir
# Measure redraw time
:timer.tc(fn ->
  TermUI.Runtime.force_render(Process.whereis(TermUI.Runtime))
end)
```

**Expected**: < 50ms for typical screen size

## Terminal Emulator Compatibility

Test with different terminals:

- [ ] iTerm2 (macOS)
- [ ] Terminal.app (macOS)
- [ ] Alacritty
- [ ] Kitty
- [ ] GNOME Terminal
- [ ] Konsole
- [ ] Windows Terminal

Note any terminals where Ctrl+L doesn't work or behaves differently.

## Regression Testing

After making changes to the redraw implementation:

1. Run all Test Scenarios above
2. Verify no new warnings during compilation
3. Run full test suite: `mix test`
4. Test on multiple terminal emulators
5. Check for memory leaks with `:observer`

## Success Criteria

Ctrl+L implementation is considered working correctly if:

✅ Screen clears completely and instantly
✅ Full UI redraws within 50ms
✅ No data loss (input, history, scroll position preserved)
✅ Works in all UI states (normal, logs open, scrolled)
✅ No connection interruption
✅ No performance degradation
✅ No memory leaks with repeated use
✅ Compatible with major terminal emulators

## Reporting Issues

If you find bugs during testing:

1. Note the terminal emulator and version
2. Record exact steps to reproduce
3. Check logs with F8
4. Capture screenshot if visual issue
5. Note any error messages
6. Test if issue persists after restart

Report in GitHub issues with:
- OS and terminal details
- Reproduction steps
- Expected vs actual behavior
- Relevant logs
- Screenshots if applicable

## Implementation Verification

The current implementation uses a state counter to trigger re-renders:

**How it works**:
1. Ctrl+L clears the screen with ANSI codes
2. `redraw_count` in state is incremented
3. State change triggers TermUI framework to re-render
4. Full UI redraws on next frame cycle (~16ms)

**Why this works**:
- TermUI's Elm Architecture re-renders when state changes
- Changing `redraw_count` forces state inequality check to fail
- Framework automatically schedules and performs re-render
- No need for process lookups or explicit render calls

**Verify in code**:
```elixir
# In lib/mudc/ui/app.ex
def update(:redraw, state) do
  IO.write([IO.ANSI.clear(), IO.ANSI.cursor(0, 0)])
  {%{state | redraw_count: state.redraw_count + 1}, []}
end
```