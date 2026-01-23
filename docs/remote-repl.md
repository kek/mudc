# Remote REPL Access Guide

## Overview

Mudc supports remote REPL access via Erlang's distributed node system. This allows you to connect to a running Mudc instance from a separate terminal for debugging, inspection, and administration without interrupting the UI or restarting the application.

## Quick Start

### 1. Start Mudc with Named Node

Mudc automatically generates and manages a secure cookie in `~/.config/mudc/.erlang.cookie`.
The cookie is created on first run and reused on subsequent runs.

```bash
# Using Mix task (recommended)
mix start

# Or using script
./start.sh
```

The cookie is:
- 32 bytes of cryptographically secure random data
- Stored with 0600 permissions (owner read/write only)
- Automatically regenerated if corrupted or permissions are wrong

### 2. Connect from Another Terminal

The cookie is automatically loaded from `~/.config/mudc/.erlang.cookie`.

```bash
# Using Mix task (recommended)
mix connect

# Or using script
./connect.sh
```

### 3. Inspect and Debug

```elixir
# You now have full access to the running application
iex(mudc@hostname)> Mudc.status()
:connected

iex(mudc@hostname)> Mudc.send("look")
:ok
```

## Use Cases

### Debugging Without Restarting

Connect to a running Mudc instance to:
- Inspect application state
- View process mailboxes
- Check ETS tables
- Examine GenServer state
- Test code changes
- Monitor performance

### Hot Code Reloading

```elixir
# Make changes to code, then in remote shell:
iex> recompile()

# Or recompile specific modules:
iex> r(Mudc.Network.Connection)
```

### State Inspection

```elixir
# Check connection state
iex> :sys.get_state(Mudc.Network.Connection)

# Check all supervised processes
iex> Supervisor.which_children(Mudc.Supervisor)

# View process info
iex> Process.info(Process.whereis(Mudc.Network.Connection))
```

### Log Access

The log buffer captures all application logs and can be accessed via remote shell:

```elixir
# View all logs
iex> Mudc.UI.LogBuffer.get_logs()
["10:23:45 [info] Connected to localhost:4242", ...]

# Get recent N logs (default: 20)
iex> Mudc.UI.LogBuffer.recent(20)

# Filter by log level
iex> Mudc.UI.LogBuffer.filter_by_level(:error)
iex> Mudc.UI.LogBuffer.filter_by_level(:warning)
iex> Mudc.UI.LogBuffer.filter_by_level(:info)

# Convenience functions
iex> Mudc.UI.LogBuffer.errors()     # Only error logs
iex> Mudc.UI.LogBuffer.warnings()   # Only warning logs

# Search logs (case-insensitive)
iex> Mudc.UI.LogBuffer.search("connection")
iex> Mudc.UI.LogBuffer.search("gmcp")

# Clear log buffer
iex> Mudc.UI.LogBuffer.clear()

# Using Debug helpers (easier!)
iex> Mudc.Debug.logs(20)           # Recent 20 logs
iex> Mudc.Debug.errors()           # Error logs
iex> Mudc.Debug.warnings()         # Warning logs
iex> Mudc.Debug.search_logs("tcp") # Search logs
```

The log buffer stores up to 500 lines in memory, automatically rotating older entries.

## Debug Helpers

The `Mudc.Debug` module provides convenient shortcuts for common debugging tasks:

### Quick Status Check

```elixir
# Get overall status
iex> Mudc.Debug.status()
=== Mudc Status ===
Connection: :connected
Vitals: %{hp: 100, max_hp: 150, ...}
...

# Health check all components
iex> Mudc.Debug.health_check()
=== Health Check ===
✓ Connection: #PID<0.234.0>
✓ LogBuffer: #PID<0.123.0>
...
```

### Log Access (Simplified)

```elixir
# Recent logs (default 20)
iex> Mudc.Debug.logs()
iex> Mudc.Debug.logs(50)  # Get 50 logs

# Filter by level
iex> Mudc.Debug.errors()
iex> Mudc.Debug.warnings()

# Search
iex> Mudc.Debug.search_logs("connection")
```

### Memory Analysis

```elixir
# Overview
iex> Mudc.Debug.memory()
=== Memory Usage ===
Total: 45.7 MB
Processes: 23.4 MB
...

# Top consumers
iex> Mudc.Debug.top_memory(10)
=== Top 10 Processes by Memory ===
Mudc.UI.LogBuffer (#PID<...>): 2.3 MB
...

# Find bottlenecks
iex> Mudc.Debug.mailbox_sizes()
=== Process Mailbox Sizes (non-zero) ===
Mudc.Network.Connection: 5 messages
```

### Complete Snapshot

```elixir
# Get everything in one call
iex> Mudc.Debug.dump()
============================================================
MUDC DEBUG DUMP
============================================================
=== Mudc Status ===
...
=== Health Check ===
...
=== Memory Usage ===
...
```

### Other Helpers

```elixir
# Monitor memory over time
iex> Mudc.Debug.monitor_memory(5)  # Every 5 seconds

# Trace function calls
iex> Mudc.Debug.trace(Mudc.Network.Connection)
iex> Mudc.Debug.stop_trace()

# Restart a process
iex> Mudc.Debug.restart(Mudc.Network.Connection)
```

See `lib/mudc/debug.ex` for all available functions.

### Testing Commands

```elixir
# Send commands to the MUD
iex> Mudc.send("north")
iex> Mudc.send("look")
iex> Mudc.send("score")

# Check connection status
iex> Mudc.status()
```

### GMCP Inspection

```elixir
# View GMCP state
iex> :sys.get_state(Mudc.Network.GMCP.Handler)

# Check game state
iex> Mudc.State.GameState.get_vitals()
iex> Mudc.State.GameState.get_room()
```

## Advanced Usage

### Multiple Remote Connections

You can have multiple remote shells connected simultaneously:

```bash
# Terminal 1
mix connect

# Terminal 2
mix connect
```

Note: Each `mix connect` automatically generates a unique node name.

### Custom Node Names

```bash
# Start with custom node name
mix start my_mud_client

# Connect to custom node
mix connect my_mud_client
```

### Remote Host Connection

Connect to Mudc running on a different machine:

```bash
# On remote machine (192.168.1.100), start with long name
iex --name mudc@192.168.1.100 --cookie mudc_secret_cookie -S mix

# From local machine
iex --name debug@$(hostname -f) --cookie mudc_secret_cookie --remsh mudc@192.168.1.100
```

**Note**: For remote connections across networks, ensure:
- EPMD port (4369) is open
- Dynamic port range is accessible (typically 49152-65535)
- Both nodes use the same cookie
- DNS/hostname resolution works

### Production Deployment

For production environments, use a stronger cookie:

```elixir
# In config/prod.exs or runtime.exs
config :mudc,
  cookie: System.get_env("MUDC_ERLANG_COOKIE") || :crypto.strong_rand_bytes(32)
```

Then start with:

```bash
iex --sname mudc --cookie $MUDC_ERLANG_COOKIE -S mix
```

## Security Considerations

### Cookie Security

Erlang cookies provide full access to the node. Anyone with your cookie can:
- Execute arbitrary code
- Access all data
- Crash the application

**Cookie Management in Mudc:**
- Automatically generated on first start
- Stored in `~/.config/mudc/.erlang.cookie`
- File permissions: 0600 (owner read/write only)
- 32 bytes of random data (Base64 encoded)

**To regenerate cookie:**

```bash
# Delete and restart
rm ~/.config/mudc/.erlang.cookie
mix start

# Or programmatically
iex> Mudc.Config.CookieManager.regenerate_cookie()
```

**Best practices:**
- Never commit cookie to version control
- Don't share cookie file
- Keep file permissions at 0600
- Regenerate if compromised

### Network Security

```bash
# Restrict to localhost only (use short names)
iex --sname mudc -S mix

# For remote access, use SSH tunneling
ssh -L 4369:localhost:4369 -L 9000-9100:localhost:9000-9100 user@remote-host
```

### Production Cookie Management

Mudc automatically manages cookies securely. For additional security in production:

```bash
# Verify cookie permissions
ls -la ~/.config/mudc/.erlang.cookie
# Should show: -rw------- (0600)

# Regenerate if needed
rm ~/.config/mudc/.erlang.cookie
mix start
```

## Troubleshooting

### Connection Refused

**Problem**: `Node 'mudc@hostname' not responding to pings.`

**Solutions**:
1. Check if Mudc is running: `epmd -names`
2. Verify node name matches: `hostname -s`
3. Ensure cookies match on both nodes
4. Check EPMD is running: `ps aux | grep epmd`

### Cookie Mismatch

**Problem**: Connection fails silently or with authentication error

**Solutions**:
1. Ensure both nodes use same cookie file: `~/.config/mudc/.erlang.cookie`
2. Check file permissions: `ls -la ~/.config/mudc/.erlang.cookie` (should be `-rw-------`)
3. Regenerate cookie: `rm ~/.config/mudc/.erlang.cookie && mix start`

### Cookie Issues

**Problem**: Cannot connect - cookie mismatch

**Solutions**:
1. Ensure both nodes use same cookie file: `~/.config/mudc/.erlang.cookie`
2. Check file permissions: `ls -la ~/.config/mudc/.erlang.cookie` (should be `-rw-------`)
3. Regenerate cookie: `rm ~/.config/mudc/.erlang.cookie && mix start`

**Problem**: Cookie file corrupted

**Solution**: Delete file and restart - it will regenerate automatically

### Name Resolution

**Problem**: Cannot connect to node by name

**Solutions**:
1. Use IP addresses with long names: `--name mudc@192.168.1.100`
2. Add hostname to `/etc/hosts`
3. Use fully qualified domain names

### Firewall Issues

**Problem**: Connection hangs or times out

**Solutions**:
1. Check EPMD port 4369 is open
2. Check dynamic distribution ports (9000-9100 or higher)
3. Configure specific port range in `vm.args`

## Examples

### Debug Connection Issues

```elixir
# In remote shell
iex> {:ok, socket} = :gen_tcp.connect(~c"localhost", 4242, [:binary])
iex> :gen_tcp.send(socket, "look\r\n")
iex> :gen_tcp.recv(socket, 0, 5000)
```

### Monitor Process Mailboxes

```elixir
iex> pid = Process.whereis(Mudc.Network.Connection)
iex> Process.info(pid, :message_queue_len)
iex> Process.info(pid, :messages)
```

### Check Application Environment

```elixir
iex> Application.get_all_env(:mudc)
iex> Application.get_env(:logger, :level)
```

### Trace Function Calls

```elixir
# Trace all calls to Mudc.Network.Connection
iex> :dbg.tracer()
iex> :dbg.p(:all, :c)
iex> :dbg.tpl(Mudc.Network.Connection, :_, :_)

# Stop tracing
iex> :dbg.stop()
```

### Benchmark Performance

```elixir
iex> :timer.tc(fn -> Mudc.send("look") end)
{1523, :ok}  # 1.5ms

iex> Enum.map(1..100, fn _ -> :timer.tc(fn -> Mudc.send("look") end) end)
|> Enum.map(fn {time, _} -> time end)
|> Enum.sum()
|> Kernel./(100)
```

## Best Practices

### Development Workflow

1. **Start with remote REPL enabled**: Always use `mix start` for development
2. **Keep a debug terminal open**: Have `mix connect` ready in another terminal
3. **Use observer for visualization**: `iex> :observer.start()`
4. **Enable debug logging**: Check logs frequently via `LogBuffer.get_logs()`

### Debugging Strategy

1. **Check process is alive**: `Process.whereis(ModuleName)`
2. **Inspect state first**: `:sys.get_state(pid)`
3. **Check messages**: `Process.info(pid, :messages)`
4. **Review logs**: `LogBuffer.get_logs()`
5. **Test in isolation**: Try operations manually

### Safety Tips

- **Always use `--remsh`**: This ensures exiting doesn't kill the main node
- **Don't run dangerous operations**: Be careful with `Process.exit/2`
- **Test in dev first**: Never experiment on production
- **Monitor memory**: Check `:erlang.memory()` regularly
- **Keep connections short**: Don't leave remote shells open indefinitely

## Related Commands

### Node Information

```elixir
# Current node name
iex> node()

# All connected nodes
iex> Node.list()

# Node statistics
iex> :erlang.statistics(:run_queue)
iex> :erlang.memory()
iex> :erlang.system_info(:process_count)
```

### Application Control

```elixir
# Stop application (but keep node running)
iex> Application.stop(:mudc)

# Start application
iex> Application.start(:mudc)

# Restart application
iex> Application.stop(:mudc)
iex> Application.start(:mudc)
```

### Observer Tool

```elixir
# Start Observer GUI (requires X11/display)
iex> :observer.start()

# View application tree
# View process details
# Monitor memory and CPU usage
# Inspect ETS tables
```

## Summary

Remote REPL access is a powerful debugging tool that allows you to:

- ✅ Inspect running application without restarting
- ✅ Test changes interactively
- ✅ Debug issues in real-time
- ✅ Monitor performance and state
- ✅ Access logs programmatically
- ✅ Hot reload code

Use it during development for a faster, more productive workflow.