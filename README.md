# Mudc

A MUD (Multi-User Dungeon) client for MUME, written in Elixir/OTP.

## Quick Start

```bash
# Install dependencies
mix deps.get

# Run the client
iex -S mix
iex> Mudc.run()

# Or run with remote REPL support (for debugging)
./start.sh
```

## Connection

Mudc connects to MUME via MMapper (https://github.com/MUME/MMapper).

**Important**: Make sure MMapper is running and accepting connections on `localhost:4242` before starting Mudc.

### Configuration

By default, Mudc will auto-connect to `localhost:4242` on startup. You can customize this by creating a config file at `~/.config/mudc/config.toml`:

```toml
[connection]
host = "localhost"
port = 4242
auto_connect = true
```

### Connection Commands

When the UI is running, you can use these commands:

- `/connect` - Connect to the MUD server
- `/disconnect` - Disconnect from the MUD server
- `/quit` - Exit the client

### Hotkeys

- `Ctrl+Arrow Keys` - Send directional commands (Ctrl+Up=north, Ctrl+Down=south, Ctrl+Left=west, Ctrl+Right=east)
- `F5` - Recompile code without restarting (for development)
- `Page Up/Down` - Scroll game text
- `Ctrl+C` - Quit the client



This feature is particularly useful for development and debugging without having to restart the entire client.

## Remote REPL Access

For debugging and inspection, you can connect to a running Mudc instance from a separate terminal using distributed Erlang.

### Starting with Remote REPL Enabled

```bash
# Start Mudc with named node (enables remote access)
./start.sh

# Or manually:
iex --sname mudc --cookie mudc_secret_cookie -S mix
```

### Connecting to Running Instance

In a separate terminal, connect to the running Mudc instance:

```bash
# Connect using the helper script
./connect.sh

# Or manually:
iex --sname debug --cookie mudc_secret_cookie --remsh mudc@$(hostname -s)
```

Once connected, you have full access to the running application:

```elixir
# Check connection status
Mudc.status()

# Send commands to the MUD
Mudc.send("look")

# Inspect application state
:sys.get_state(Mudc.Network.Connection)

# View logs programmatically
Mudc.UI.LogBuffer.get_logs()

# Check which processes are running
Process.whereis(Mudc.Network.Connection)
Process.whereis(TermUI.Runtime)
```

**Note**: When you exit the remote shell (Ctrl+C twice), the main Mudc application continues running. This allows non-intrusive debugging and inspection.

### Custom Node Names

```bash
# Start with custom node name
./start.sh mynode

# Connect to custom node
./connect.sh mynode

# Connect to node on different host
./connect.sh mudc othermachine
```

### Connection Status

- The bottom status bar shows connection messages and helpful command hints
- When you successfully connect, you'll see "[Connected to localhost:4242]" in the game output

If you see "DISCONNECTED" and connection errors, make sure:
1. MMapper is running
2. MMapper is configured to accept connections on port 4242
3. Your firewall isn't blocking the connection

## Prior art

- Mudlet
- Tinyfugue
- Tintin++

## Integrations

- MMapper https://github.com/MUME/MMapper
- Telnet
- GMCP
- Luerl


## Toolkit

- Elixir
- OTP
- pcharbon70/term_ui

## Roadmap

- Resize window
- More powerful support for editing the line
- Nicer drawing characters
- Hotkeys
- Being able to hot reload the code of the app in order to not have to restart
  (the app acting a little like IEx). Also being able to run arbitrary code from
  the UI.
- Split windows with the various filters for chats, messages, highlighted things
  etc.
