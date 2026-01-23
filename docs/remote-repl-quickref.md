# Remote REPL Quick Reference

## Start and Connect

```bash
# Terminal 1: Start Mudc
./start.sh

# Terminal 2: Connect remotely
./connect.sh
```

## Common Commands

### Connection & Status
```elixir
# Check connection status
Mudc.status()

# Connect to MUD
Mudc.connect()

# Disconnect
Mudc.disconnect()

# Send command
Mudc.send("look")
```

### State Inspection
```elixir
# Get process state
:sys.get_state(Mudc.Network.Connection)
:sys.get_state(Mudc.Network.GMCP.Handler)

# Check if process is alive
Process.whereis(Mudc.Network.Connection)
Process.whereis(TermUI.Runtime)

# List all supervised processes
Supervisor.which_children(Mudc.Supervisor)

# Process info
pid = Process.whereis(Mudc.Network.Connection)
Process.info(pid)
Process.info(pid, :message_queue_len)
Process.info(pid, :messages)
```

### Application Control
```elixir
# Recompile code
recompile()

# Reload specific module
r(Mudc.Network.Connection)

# Stop/start application
Application.stop(:mudc)
Application.start(:mudc)

# Get config
Application.get_all_env(:mudc)
Application.get_env(:mudc, :node_name)
```

### Game State
```elixir
# Get vitals (HP, mana, etc.)
Mudc.State.GameState.get_vitals()

# Get room info
Mudc.State.GameState.get_room()

# View all game state
Mudc.State.GameState.dump()
```

### Logging
```elixir
# Get all logs
Mudc.UI.LogBuffer.get_logs()

# Get recent logs (default: 20)
Mudc.UI.LogBuffer.recent(20)

# Get only errors
Mudc.UI.LogBuffer.errors()

# Get only warnings
Mudc.UI.LogBuffer.warnings()

# Filter by level
Mudc.UI.LogBuffer.filter_by_level(:error)
Mudc.UI.LogBuffer.filter_by_level(:info)

# Search logs
Mudc.UI.LogBuffer.search("connection")

# Clear logs
Mudc.UI.LogBuffer.clear()
```

### Debug Helpers (Quick Access)
```elixir
# Overall status
Mudc.Debug.status()

# Health check all components
Mudc.Debug.health_check()

# Recent logs
Mudc.Debug.logs(20)

# Only errors
Mudc.Debug.errors()

# Search logs
Mudc.Debug.search_logs("gmcp")

# Memory usage
Mudc.Debug.memory()

# Top memory consumers
Mudc.Debug.top_memory(10)

# Mailbox sizes (find bottlenecks)
Mudc.Debug.mailbox_sizes()

# Complete dump
Mudc.Debug.dump()
```

### System Info
```elixir
# Current node
node()

# Connected nodes
Node.list()

# System stats
:erlang.memory()
:erlang.system_info(:process_count)
:erlang.statistics(:run_queue)

# Application list
Application.started_applications()
```

### Debugging Tools
```elixir
# Start Observer GUI
:observer.start()

# Get process tree
Process.list() |> length()

# Memory usage
:erlang.memory(:total)
:erlang.memory(:processes)

# Trace function calls
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tpl(Mudc.Network.Connection, :send_command, :_)
:dbg.stop()
```

## Exit

```bash
# Press Ctrl+C twice to disconnect
# (leaves Mudc running)
```

## Quick Debugging Workflow

```elixir
# 1. Check if everything is running
Mudc.Debug.health_check()

# 2. Check recent logs for errors
Mudc.Debug.errors()

# 3. Check memory usage
Mudc.Debug.memory()

# 4. Get full status
Mudc.Debug.status()

# 5. If something is wrong, check logs
Mudc.Debug.search_logs("error")
```

## Tips

- Use `h Module.function` for help
- Use `i value` to inspect a value
- Use `v(n)` to recall previous result (e.g., `v(1)`)
- Use Tab for autocomplete
- Changes made in remote shell are temporary unless you recompile
- Use `Mudc.Debug.dump()` for a complete snapshot

## Manual Connection

```bash
# Start with named node
iex --sname mudc --cookie mudc_secret_cookie -S mix

# Connect remotely
iex --sname debug --cookie mudc_secret_cookie --remsh mudc@$(hostname -s)
```

## See Also

- `docs/remote-repl.md` - Full documentation
- `docs/remote-repl-examples.md` - Practical examples
- `README.md` - General usage
- `docs/keyboard-shortcuts.md` - UI hotkeys
- `lib/mudc/debug.ex` - Debug helper module source