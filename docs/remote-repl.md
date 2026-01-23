# Remote REPL Access Guide

## Overview

Mudc supports remote REPL access via Erlang's distributed node system. This allows you to connect to a running Mudc instance from a separate terminal for debugging, inspection, and administration without interrupting the UI or restarting the application.

## Quick Start

### 1. Start Mudc with Named Node

```bash
# Using the helper script (recommended)
./start.sh

# Or manually
iex --sname mudc --cookie mudc_secret_cookie -S mix
```

### 2. Connect from Another Terminal

```bash
# Using the helper script (recommended)
./connect.sh

# Or manually
iex --sname debug --cookie mudc_secret_cookie --remsh mudc@$(hostname -s)
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

```elixir
# View recent logs
iex> Mudc.UI.LogBuffer.get_logs()

# View specific log levels
iex> Mudc.UI.LogBuffer.get_logs() |> Enum.filter(&String.contains?(&1, "[error]"))
```

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
./connect.sh

# Terminal 2 (generates unique node name)
iex --sname debug2 --cookie mudc_secret_cookie --remsh mudc@$(hostname -s)
```

### Custom Node Names

```bash
# Start with custom node name
./start.sh my_mud_client

# Connect to custom node
./connect.sh my_mud_client
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

The Erlang cookie acts as authentication. Anyone with the cookie can:
- Connect to your node
- Execute arbitrary code
- Access all data
- Crash the application

**Best practices:**
- Use strong, random cookies in production
- Store cookies in environment variables, not in code
- Restrict filesystem permissions on `.erlang.cookie`
- Use firewalls to restrict EPMD and distribution ports

### Network Security

```bash
# Restrict to localhost only (use short names)
iex --sname mudc -S mix

# For remote access, use SSH tunneling
ssh -L 4369:localhost:4369 -L 9000-9100:localhost:9000-9100 user@remote-host
```

### Production Cookie Management

```bash
# Generate a strong cookie
openssl rand -base64 32 > .erlang.cookie
chmod 400 .erlang.cookie

# Use it when starting
export MUDC_COOKIE=$(cat .erlang.cookie)
iex --sname mudc --cookie "$MUDC_COOKIE" -S mix
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
1. Verify both nodes use same cookie
2. Check `~/.erlang.cookie` if not specified explicitly
3. Explicitly set cookie on both nodes

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

1. **Start with remote REPL enabled**: Always use `./start.sh` for development
2. **Keep a debug terminal open**: Have `./connect.sh` ready in another terminal
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