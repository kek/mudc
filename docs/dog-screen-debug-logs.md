# Dog Screen - Debug Logs Viewer

## Overview

The Dog Screen (F4) is a built-in debug logs viewer that displays real-time application logs with color-coded log levels. It provides an always-visible debug console without needing to connect via remote REPL.

## Accessing the Dog Screen

Press **F4** at any time to switch to the Dog Screen. Press **F3** to return to the game view.

```
┌─────────────────────────────────────────────────────────┐
│ F3: Game | F4: Dog | F5: Cat                            │
├─────────────────────────────────────────────────────────┤
│        / \__                                            │
│       (    @\___                                        │
│       /         O                                       │
│      /   (_____/                                        │
│     /_____/   U                                         │
├─────────────────────────────────────────────────────────┤
│ DEBUG LOGS (most recent first):                        │
├─────────────────────────────────────────────────────────┤
│ 10:23:45 [info] Connected to localhost:4242            │
│ 10:23:44 [debug] Sending GMCP handshake                │
│ 10:23:43 [warning] Retrying connection...              │
│ 10:23:40 [error] Connection timeout                    │
│ ...                                                     │
└─────────────────────────────────────────────────────────┘
```

## Features

### Real-Time Updates

- Logs appear automatically as they are generated
- No need to refresh or switch screens
- Shows most recent logs first
- Automatically scrolls as new logs arrive

### Color-Coded Log Levels

Logs are color-coded by severity level:

- **Red (Bold)**: `[error]` - Critical errors that need immediate attention
- **Yellow**: `[warning]` - Warning messages about potential issues
- **Green**: `[info]` - Informational messages about normal operations
- **Cyan (Dim)**: `[debug]` - Detailed debugging information
- **White**: Other messages

### What's Logged

The Dog Screen shows all application logs including:

- Connection events (connect, disconnect, errors)
- Network activity (sending/receiving data)
- GMCP protocol messages
- Scripting engine events
- Configuration loading
- Error stack traces
- Performance warnings
- State changes

## Common Use Cases

### 1. Connection Troubleshooting

```
# Press F4 to view logs
[error] Connection failed: :econnrefused
[info] Retrying connection to localhost:4242
[warning] MMapper not responding on port 4242
```

**Solution**: Check that MMapper is running and listening on port 4242.

### 2. GMCP Debugging

```
[debug] Sending GMCP: Core.Hello
[info] GMCP enabled packages: ["Char.Vitals", "Room.Info"]
[warning] Unknown GMCP package: CustomPackage
```

**Solution**: Verify GMCP configuration and supported packages.

### 3. Script Errors

```
[error] Lua script error: attempt to call nil value
[debug] Script 'triggers.lua' loaded successfully
[warning] Script function 'on_text' not found
```

**Solution**: Check script syntax and function names.

### 4. Performance Issues

```
[warning] Message queue length: 1000+ messages
[debug] Processing took 500ms (expected < 100ms)
[info] Memory usage: 150MB
```

**Solution**: Investigate bottlenecks or memory leaks.

## Hotkeys

| Key | Action |
|-----|--------|
| `F4` | Switch to Dog Screen (from any screen) |
| `F3` | Return to Game Screen |
| `F5` | Switch to Cat Screen |

## Limitations

- Shows only the most recent logs that fit on screen (typically 10-30 lines depending on terminal size)
- Log buffer limited to 500 lines total (older logs are discarded)
- No scrolling within the Dog Screen (logs auto-scroll to show newest)
- Cannot filter or search logs in the UI (use remote REPL for advanced filtering)

## Advanced Log Access

For more advanced log inspection, use the remote REPL:

```bash
# Connect to running instance
./connect.sh

# View all logs
iex> Mudc.UI.LogBuffer.get_logs()

# Filter by level
iex> Mudc.UI.LogBuffer.errors()
iex> Mudc.UI.LogBuffer.warnings()

# Search logs
iex> Mudc.UI.LogBuffer.search("connection")

# Get recent N logs
iex> Mudc.UI.LogBuffer.recent(50)
```

See `docs/remote-repl.md` for complete remote REPL documentation.

## Comparison: Dog Screen vs Remote REPL

| Feature | Dog Screen (F4) | Remote REPL |
|---------|-----------------|-------------|
| Access | Press F4 | `./connect.sh` |
| Real-time | ✅ Yes | ✅ Yes |
| Scrolling | ❌ No | ✅ Yes (unlimited) |
| Filtering | ❌ No | ✅ Yes (by level, search) |
| History | 500 lines | All logs |
| Always visible | ✅ Yes | ❌ Requires separate terminal |
| Color-coded | ✅ Yes | ⚠️ Depends on terminal |
| Ease of use | ✅ Very easy | ⚠️ Requires IEx knowledge |

**Recommendation**: 
- Use **Dog Screen** for quick checks and real-time monitoring during gameplay
- Use **Remote REPL** for detailed debugging, searching, and log analysis

## Tips

1. **Quick Check**: Press F4 after any unexpected behavior to see what happened
2. **Error Hunting**: Look for red `[error]` messages first
3. **Performance**: Watch for `[warning]` messages about slow operations
4. **Return Quickly**: Press F3 to return to game without interrupting your session
5. **Log Buffer**: Remember only the most recent 500 lines are kept in memory

## Examples

### Example 1: Connection Failed

```
[error] 10:15:23 Connection refused by localhost:4242
[info]  10:15:20 Attempting to connect to localhost:4242
[debug] 10:15:18 Connection process started
```

**Action**: Start MMapper, then type `/connect`

### Example 2: GMCP Not Working

```
[warning] 10:20:15 GMCP message ignored: invalid format
[info]    10:20:10 GMCP handshake completed
[debug]   10:20:08 Sending GMCP.Core.Hello
```

**Action**: Check MMapper GMCP settings

### Example 3: Script Loaded

```
[info]  10:25:30 Script 'combat.lua' loaded successfully
[debug] 10:25:29 Loading scripts from ~/.config/mudc/scripts/
[info]  10:25:28 Scripting engine initialized
```

**Action**: Everything working correctly!

## Configuration

The log buffer size (500 lines) is defined in `lib/mudc/ui/log_buffer.ex`:

```elixir
@max_lines 500
```

To change the buffer size, edit this value and recompile with `Ctrl+F5`.

## Related Documentation

- [Remote REPL Guide](remote-repl.md) - Advanced log access and debugging
- [Remote REPL Quick Reference](remote-repl-quickref.md) - LogBuffer functions
- [Keyboard Shortcuts](keyboard-shortcuts.md) - All hotkeys including F3/F4/F5

## See Also

- `lib/mudc/ui/log_buffer.ex` - Log buffer implementation
- `lib/mudc/ui/log_handler.ex` - Logger handler that captures logs
- `lib/mudc/debug.ex` - Debug helper functions for remote REPL