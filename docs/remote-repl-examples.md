# Remote REPL - Practical Examples

This document shows real-world examples of using the remote REPL for debugging and development.

## Example 1: Debugging Connection Issues

**Scenario**: The MUD client won't connect to the server.

```bash
# Terminal 1: Start Mudc
./start.sh

# Terminal 2: Connect to debug
./connect.sh
```

```elixir
# Check if connection process is alive
iex(mudc@hostname)> Process.whereis(Mudc.Network.Connection)
#PID<0.234.0>

# Get connection state
iex(mudc@hostname)> :sys.get_state(Mudc.Network.Connection)
%{
  socket: nil,
  host: ~c"localhost",
  port: 4242,
  buffer: "",
  connected: false
}

# Try to connect manually
iex(mudc@hostname)> :gen_tcp.connect(~c"localhost", 4242, [:binary, active: false])
{:error, :econnrefused}

# Ah! MMapper isn't running. Start MMapper, then:
iex(mudc@hostname)> Mudc.connect()
:ok

# Verify connection
iex(mudc@hostname)> Mudc.status()
:connected
```

## Example 2: Testing GMCP Functionality

**Scenario**: Vitals aren't updating in the UI.

```elixir
# Check GMCP handler state
iex> :sys.get_state(Mudc.Network.GMCP.Handler)
%{
  supported_packages: ["Char", "Char.Vitals", "Room"],
  enabled: true
}

# Check game state
iex> Mudc.State.GameState.get_vitals()
%{hp: 100, max_hp: 150, mana: 80, max_mana: 120}

# Subscribe to GMCP events to watch updates
iex> Mudc.Events.Bus.subscribe(:state_changed)
:ok

# Send a command that should trigger vitals update
iex> Mudc.send("score")
:ok

# Wait for message
iex> flush()
{:event, :state_changed, {:vitals, %{hp: 98, max_hp: 150, ...}}}
:ok

# Vitals are updating! Check if UI is subscribed
iex> :sys.get_state(Process.whereis(TermUI.Runtime))
# ... inspect state ...
```

## Example 3: Hot Code Reloading

**Scenario**: You fixed a bug and want to test without restarting.

```elixir
# Make changes to lib/mudc/network/connection.ex in your editor
# Then in remote shell:

iex> recompile()
Compiling 1 file (.ex)
:ok

# Or reload specific module
iex> r(Mudc.Network.Connection)
{:reloaded, Mudc.Network.Connection, [Mudc.Network.Connection]}

# Test the fix
iex> Mudc.send("look")
:ok

# If you need to restart the GenServer with new code:
iex> pid = Process.whereis(Mudc.Network.Connection)
iex> Supervisor.terminate_child(Mudc.Supervisor, Mudc.Network.Connection)
iex> Supervisor.restart_child(Mudc.Supervisor, Mudc.Network.Connection)
```

## Example 4: Inspecting Network Traffic

**Scenario**: You want to see raw data from the MUD server.

```elixir
# Get the connection socket
iex> state = :sys.get_state(Mudc.Network.Connection)
iex> socket = state.socket

# Send raw data
iex> :gen_tcp.send(socket, "look\r\n")
:ok

# Receive raw data (if socket is in passive mode)
iex> :gen_tcp.recv(socket, 0, 5000)
{:ok, "\e[32mYou are standing in a grassy field...\e[0m\r\n"}

# Or trace all messages to the connection process
iex> pid = Process.whereis(Mudc.Network.Connection)
iex> :sys.trace(pid, true)
:ok

iex> Mudc.send("north")
*DBG* Mudc.Network.Connection got call send_command("north")
*DBG* Mudc.Network.Connection sent "north\r\n" to socket
:ok

iex> :sys.trace(pid, false)
:ok
```

## Example 5: Memory Leak Investigation

**Scenario**: Memory usage keeps growing.

```elixir
# Check overall memory
iex> :erlang.memory(:total) / 1024 / 1024
45.7  # MB

# Check which processes use most memory
iex> Process.list()
|> Enum.map(fn pid -> {pid, Process.info(pid, :memory)} end)
|> Enum.sort_by(fn {_, {:memory, mem}} -> mem end, :desc)
|> Enum.take(10)
[
  {#PID<0.234.0>, {:memory, 12345678}},
  {#PID<0.156.0>, {:memory, 9876543}},
  ...
]

# Inspect the biggest offender
iex> pid = #PID<0.234.0>
iex> Process.info(pid, :registered_name)
{:registered_name, Mudc.UI.LogBuffer}

# Check its state
iex> state = :sys.get_state(pid)
iex> length(state.lines)
50000  # Aha! Log buffer is too large

# Check the max_lines setting
iex> Mudc.UI.LogBuffer.__info__(:attributes)
# ... shows @max_lines 500 ...

# Something is wrong. Check the buffer directly
iex> logs = Mudc.UI.LogBuffer.get_logs()
iex> length(logs)
50000

# Clear the buffer (if there's a clear function) or restart the process
```

## Example 6: Performance Profiling

**Scenario**: Commands are taking too long to process.

```elixir
# Time a command
iex> :timer.tc(fn -> Mudc.send("look") end)
{1234, :ok}  # 1.234 milliseconds

# Profile multiple commands
iex> times = for _ <- 1..100 do
...>   {time, _} = :timer.tc(fn -> Mudc.send("look") end)
...>   time
...> end
iex> Enum.sum(times) / length(times)
1456.7  # Average 1.4ms

# Use :fprof for detailed profiling
iex> :fprof.trace([:start, {:procs, Process.whereis(Mudc.Network.Connection)}])
iex> Mudc.send("look")
iex> :fprof.trace(:stop)
iex> :fprof.profile()
iex> :fprof.analyse([{:dest, '/tmp/fprof_analysis.txt'}])

# Use :eprof for simpler profiling
iex> :eprof.start()
iex> :eprof.profile([], fn -> Mudc.send("look") end)
iex> :eprof.analyze()
```

## Example 7: Scripting System Debug

**Scenario**: Lua scripts aren't executing properly.

```elixir
# Check scripting engine state
iex> :sys.get_state(Mudc.Scripting.Engine)
%{lua_state: #Reference<...>, scripts: %{}}

# Try to load a script manually
iex> script = """
...> function on_text(line)
...>   if string.find(line, "Elf") then
...>     send("kill elf")
...>   end
...> end
...> """

iex> Mudc.Scripting.Engine.load_script("test", script)
{:ok, "test"}

# Test the script
iex> Mudc.Scripting.Engine.call_function("on_text", ["An Elf arrives from the north."])
{:ok, nil}

# Check logs for any script errors
iex> Mudc.UI.LogBuffer.get_logs()
|> Enum.filter(&String.contains?(&1, "script"))
```

## Example 8: Event System Monitoring

**Scenario**: Events aren't being delivered properly.

```elixir
# Subscribe to all event topics
iex> Mudc.Events.Bus.subscribe(:game_text)
iex> Mudc.Events.Bus.subscribe(:connection)
iex> Mudc.Events.Bus.subscribe(:state_changed)

# Send a command
iex> Mudc.send("look")

# Check mailbox
iex> flush()
{:event, :game_text, {:text, "You are in a dark forest..."}}
{:event, :game_text, :prompt}
:ok

# Check who else is subscribed
iex> Registry.lookup(Mudc.Events.Bus, :game_text)
[
  {#PID<0.234.0>, nil},  # UI.App
  {#PID<0.345.0>, nil}   # Your shell
]

# Unsubscribe
iex> Mudc.Events.Bus.unsubscribe(:game_text)
:ok
```

## Example 9: Configuration Debugging

**Scenario**: Config values aren't loading correctly.

```elixir
# Check all application config
iex> Application.get_all_env(:mudc)
[
  node_name: :mudc,
  cookie: :mudc_secret_cookie
]

# Check specific config
iex> Application.get_env(:mudc, :node_name)
:mudc

# Check logger config
iex> Application.get_env(:logger, :level)
:debug

# Load config from file
iex> {:ok, config} = Mudc.Config.Manager.load_config()
iex> config
%{
  connection: %{host: "localhost", port: 4242, auto_connect: true},
  ...
}

# Update config at runtime
iex> Application.put_env(:logger, :level, :info)
:ok
```

## Example 10: Observer for Visual Debugging

**Scenario**: You want a graphical view of the system.

```elixir
# Start Observer (requires X11/display)
iex> :observer.start()

# Navigate through:
# - Applications tab: See supervision tree
# - Processes tab: Sort by memory/reductions
# - Table Viewer: Inspect ETS tables
# - Trace: Set up message tracing
# - System tab: Overall system info

# If you're on a remote system without display:
# Use SSH with X11 forwarding:
ssh -X user@remote-host
./connect.sh
iex> :observer.start()
```

## Tips and Tricks

### Quick State Dump

```elixir
# Define a helper function in your remote shell
iex> dump_state = fn ->
...>   IO.puts("=== Mudc State Dump ===")
...>   IO.puts("Connection: #{inspect(Mudc.status())}")
...>   IO.puts("Vitals: #{inspect(Mudc.State.GameState.get_vitals())}")
...>   IO.puts("Room: #{inspect(Mudc.State.GameState.get_room())}")
...>   IO.puts("Processes: #{length(Process.list())}")
...>   IO.puts("Memory: #{:erlang.memory(:total) / 1024 / 1024} MB")
...> end

iex> dump_state.()
```

### Persistent Connection

```elixir
# Add to your ~/.iex.exs for custom helpers
defmodule MudcDebug do
  def quick_connect do
    node = :"mudc@#{:net_adm.localhost()}"
    Node.connect(node)
  end
  
  def state(module) do
    module
    |> Process.whereis()
    |> :sys.get_state()
  end
end

# Then in any IEx session:
iex> MudcDebug.quick_connect()
iex> MudcDebug.state(Mudc.Network.Connection)
```

### Automated Monitoring

```elixir
# Set up a monitoring loop
iex> monitor_task = Task.async(fn ->
...>   Stream.interval(5000)
...>   |> Stream.each(fn _ ->
...>     IO.puts("Memory: #{:erlang.memory(:total) / 1024 / 1024} MB")
...>     IO.puts("Processes: #{length(Process.list())}")
...>   end)
...>   |> Stream.run()
...> end)

# Stop monitoring
iex> Task.shutdown(monitor_task)
```

## Common Patterns

### Check if Something is Working

```elixir
# Pattern: Check if process exists -> Get state -> Test function
iex> pid = Process.whereis(ModuleName)
iex> is_pid(pid)  # true means it's running
iex> state = :sys.get_state(pid)
iex> ModuleName.some_function()  # Test it
```

### Restart a Crashed Process

```elixir
# Pattern: Check supervisor -> Restart child
iex> Supervisor.which_children(Mudc.Supervisor)
iex> Supervisor.restart_child(Mudc.Supervisor, Mudc.Network.Connection)
```

### Find Memory Leaks

```elixir
# Pattern: Snapshot -> Wait -> Snapshot -> Compare
iex> before = :erlang.memory()
iex> # Do something that might leak
iex> after_mem = :erlang.memory()
iex> Enum.map([:total, :processes, :binary, :ets], fn key ->
...>   {key, after_mem[key] - before[key]}
...> end)
```

## Summary

Remote REPL is invaluable for:
- ✅ Real-time debugging
- ✅ State inspection
- ✅ Performance profiling
- ✅ Hot code reloading
- ✅ Testing fixes without restart
- ✅ Investigating production issues

Keep a terminal with `./connect.sh` ready during development for maximum productivity!