# Game Logging

## Overview

Mudc automatically logs all game output to a file for later review, debugging, or analysis.

## Log File Location

**Default**: `~/.config/mudc/game.log`

The log file is created automatically when Mudc starts and contains timestamped game text with ANSI color codes preserved.

## Log Format

```
=== Session started at 14:30:25 ===
[14:30:26] You are standing in a room.
[14:30:27] A monster attacks you!
[14:30:28] You flee!
=== Session ended at 14:35:10 ===
```

Each line is prefixed with a timestamp in `[HH:MM:SS]` format.

## Log Rotation

The log file automatically rotates when it exceeds 10 MB. When rotation occurs:

1. Current log is renamed to `game.YYYYMMDD-HHMMSS.log`
2. New `game.log` file is created
3. Session continues logging to new file

Example rotated files:
```
~/.config/mudc/
├── game.log                    # Current session
├── game.20260127-143025.log    # Rotated log 1
└── game.20260127-120015.log    # Rotated log 2
```

## Manual Rotation

You can manually rotate the log file from the Elixir console:

```elixir
iex> Mudc.Logging.GameLogger.rotate()
:ok
```

## Viewing Logs

### Tail current session
```bash
tail -f ~/.config/mudc/game.log
```

### View last 100 lines
```bash
tail -n 100 ~/.config/mudc/game.log
```

### Search logs
```bash
grep "monster" ~/.config/mudc/game.log
```

### View all logs
```bash
cat ~/.config/mudc/game.*.log | less
```

## Log Contents

The logger captures:
- ✅ All game text with ANSI color codes
- ✅ System messages
- ✅ GMCP data (if displayed as text)
- ✅ Session start/end markers

The logger does NOT capture:
- ❌ Commands you type (only responses)
- ❌ Debug logs (use F4 screen for those)
- ❌ UI state changes

## Performance

- Logging is asynchronous (non-blocking)
- Minimal performance impact
- UTF-8 encoding supported
- File is flushed automatically

## Configuration

Currently, log settings are hardcoded:

```elixir
@log_dir "~/.config/mudc"
@log_file "game.log"
@max_log_size 10 * 1024 * 1024  # 10 MB
```

To customize, edit `lib/mudc/logging/game_logger.ex`.

Future enhancement: Add to `config.toml`:
```toml
[logging]
enabled = true
log_dir = "~/.config/mudc"
log_file = "game.log"
max_size_mb = 10
rotation_enabled = true
```

## Troubleshooting

### Log file not created

Check permissions:
```bash
ls -la ~/.config/mudc/
```

Ensure directory is writable:
```bash
mkdir -p ~/.config/mudc
chmod 755 ~/.config/mudc
```

### Log file too large

Manually rotate:
```bash
cd ~/.config/mudc
mv game.log game.$(date +%Y%m%d-%H%M%S).log
```

Or clean old logs:
```bash
cd ~/.config/mudc
rm game.*.log  # Remove all rotated logs
```

### Missing timestamps

Timestamps use system local time. Check:
```bash
date
```

## Implementation Details

The `GameLogger` GenServer:
- Subscribes to `:game_text` events from Event Bus
- Writes text with timestamps to file
- Monitors file size and rotates when needed
- Closes file cleanly on shutdown

Located at: `lib/mudc/logging/game_logger.ex`

## See Also

- [Event Bus Documentation](./event-bus.md) - Event system
- [Architecture Documentation](./architecture.md) - System design
