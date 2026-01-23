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

# Get recent logs
Mudc.UI.LogBuffer.get_logs() |> Enum.take(-20)

# Filter by level
logs = Mudc.UI.LogBuffer.get_logs()
Enum.filter(logs, &String.contains?(&1, "[error]"))
Enum.filter(logs, &String.contains?(&1, "[warning]"))
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

## Tips

- Use `h Module.function` for help
- Use `i value` to inspect a value
- Use `v(n)` to recall previous result (e.g., `v(1)`)
- Use Tab for autocomplete
- Changes made in remote shell are temporary unless you recompile

## Manual Connection

```bash
# Start with named node
iex --sname mudc --cookie mudc_secret_cookie -S mix

# Connect remotely
iex --sname debug --cookie mudc_secret_cookie --remsh mudc@$(hostname -s)
```

## See Also

- `docs/remote-repl.md` - Full documentation
- `README.md` - General usage
- `docs/keyboard-shortcuts.md` - UI hotkeys