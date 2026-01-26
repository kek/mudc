# Protocol Documentation

## Overview

Mudc implements the Telnet protocol (RFC 854) with GMCP (Generic MUD Communication Protocol) extension for communication with MUD servers and proxies like MMapper.

## Architecture

```
TCP Socket (raw bytes)
    ↓
Connection.Socket
    ↓
Protocol.Dispatcher (Telnet parser)
    ├─→ Text → Event Bus (:game_text)
    ├─→ Telnet commands → Responses
    └─→ GMCP data → GMCP.Handler
            ↓
        Event Bus (:gmcp)
            ↓
        State.GameState (ETS storage)
```

## Telnet Protocol

### Overview

Telnet is a protocol for bidirectional text communication over TCP. MUDs use Telnet with various extensions (options) for features like ANSI colors, GMCP, compression, etc.

### Telnet Commands

Telnet uses special command sequences starting with IAC (Interpret As Command) byte:

```
IAC = 255 (0xFF)
```

#### Command Codes

```elixir
# From Mudc.Network.Telnet.Constants

@iac 255    # Interpret As Command
@will 251   # Will do option
@wont 252   # Won't do option
@do 253     # Do option
@dont 254   # Don't do option
@sb 250     # Subnegotiation Begin
@se 240     # Subnegotiation End
```

#### Option Codes

```elixir
@opt_echo 1        # Echo
@opt_sga 3         # Suppress Go Ahead
@opt_terminal 24   # Terminal Type
@opt_naws 31       # Negotiate About Window Size
@opt_eor 25        # End of Record
@opt_gmcp 201      # Generic MUD Communication Protocol
```

### Telnet Option Negotiation

When connecting, client and server negotiate which options to enable:

```
Server → Client: IAC DO GMCP
Client → Server: IAC WILL GMCP

Server → Client: IAC WILL ECHO
Client → Server: IAC DO ECHO
```

**Mudc's Default Responses**:
- Accepts GMCP (IAC DO GMCP → IAC WILL GMCP)
- Accepts Suppress Go Ahead (IAC DO SGA → IAC WILL SGA)
- Rejects other options (IAC DO X → IAC WONT X)

### Telnet Subnegotiation

Some options use subnegotiation for additional data:

```
IAC SB <option> <data> IAC SE
```

Example: GMCP message
```
IAC SB GMCP "room.info" {"name": "Forest"} IAC SE
```

### ANSI Escape Sequences

MUDs use ANSI codes for colors and formatting:

```
\e[0m   - Reset
\e[31m  - Red text
\e[32m  - Green text
\e[1m   - Bold
\e[4m   - Underline
```

**Mudc Handling**:
- Preserves ANSI codes for display
- Strips ANSI for trigger matching
- Publishes both versions on Event Bus

Example:
```elixir
# Raw from server
"\e[32mYou see a forest.\e[0m"

# Published events
{:event, :game_text, {:text, "\e[32mYou see a forest.\e[0m"}}
{:event, :game_text, {:plain_text, "You see a forest."}}
```

## GMCP (Generic MUD Communication Protocol)

### Overview

GMCP is a Telnet subnegotiation protocol for structured data exchange between MUD and client. It uses JSON payloads with module-based namespacing.

**Specification**: https://www.gammon.com.au/gmcp

### GMCP Message Format

```
IAC SB GMCP <module> <json> IAC SE
```

Example:
```
IAC SB GMCP "room.info" {"name": "Market Square", "area": "Bree"} IAC SE
```

### GMCP Modules

Common GMCP modules used by MUDs:

#### char.vitals

Character vitals (HP, mana, movement, etc.)

```json
{
  "hp": 120,
  "max_hp": 150,
  "mana": 80,
  "max_mana": 100,
  "moves": 200,
  "max_moves": 250
}
```

#### char.status

Character status (level, alignment, etc.)

```json
{
  "level": 10,
  "alignment": "good",
  "tnl": 5000
}
```

#### room.info

Current room information

```json
{
  "name": "Market Square",
  "area": "Bree",
  "terrain": "city",
  "exits": {"n": "1234", "s": "1235", "e": "1236"}
}
```

#### comm.channel

Chat channel messages

```json
{
  "channel": "gossip",
  "player": "Alice",
  "message": "Hello everyone!"
}
```

### GMCP Flow in Mudc

1. **Server sends GMCP**:
   ```
   IAC SB GMCP "char.vitals" {"hp": 120, "max_hp": 150} IAC SE
   ```

2. **Socket receives and forwards to Dispatcher**

3. **Dispatcher extracts GMCP**:
   - Detects IAC SB GMCP
   - Extracts module name: "char.vitals"
   - Extracts JSON: {"hp": 120, "max_hp": 150}
   - Forwards to GMCP.Handler

4. **GMCP.Handler processes**:
   - Parses JSON
   - Routes by module name
   - Updates GameState
   - Publishes event

5. **Event published**:
   ```elixir
   {:event, :gmcp, {:vitals, %{hp: 120, max_hp: 150}}}
   ```

6. **Subscribers notified**:
   - UI.App updates vitals display
   - Scripts can react to vitals changes

### Sending GMCP

Mudc can send GMCP to enable features:

```elixir
# Enable GMCP module
Mudc.Network.GMCP.Handler.send_gmcp("core.hello", %{
  client: "Mudc",
  version: "0.1.0"
})

# Request specific data
Mudc.Network.GMCP.Handler.send_gmcp("request.room", %{})
```

This sends:
```
IAC SB GMCP "core.hello" {"client":"Mudc","version":"0.1.0"} IAC SE
```

### GMCP Events in Mudc

GMCP messages are published as events:

```elixir
# Subscribe to GMCP events
Mudc.Events.Bus.subscribe(:gmcp)

receive do
  {:event, :gmcp, {:vitals, vitals}} ->
    IO.puts("HP: #{vitals.hp}/#{vitals.max_hp}")

  {:event, :gmcp, {:room, room}} ->
    IO.puts("Room: #{room.name}")

  {:event, :gmcp, {:gmcp, module, data}} ->
    # Catch-all for unhandled modules
    IO.puts("GMCP #{module}: #{inspect(data)}")
end
```

## Protocol.Dispatcher

### Responsibilities

Protocol.Dispatcher is the main protocol handler:

1. **Telnet Parsing**: Parses IAC sequences
2. **Option Negotiation**: Responds to WILL/WONT/DO/DONT
3. **Subnegotiation**: Handles IAC SB ... IAC SE
4. **GMCP Extraction**: Extracts GMCP messages
5. **Text Publishing**: Publishes game text to Event Bus
6. **Response Generation**: Generates Telnet responses

### Processing Pipeline

```
Raw bytes from socket
    ↓
Parse Telnet commands (IAC sequences)
    ↓
Handle options (WILL/WONT/DO/DONT)
    ↓
Extract subnegotiations (GMCP, NAWS, etc.)
    ↓
Strip ANSI codes (for trigger matching)
    ↓
Publish events
    ↓
Return response (if needed)
```

### Example Processing

**Input** (from socket):
```
<<255, 253, 201, 255, 250, 201, "room.info", 32, "{\"name\":\"Forest\"}", 255, 240, "You see a forest.\r\n">>
```

**Parsed**:
1. IAC DO GMCP (255, 253, 201)
   - Response: IAC WILL GMCP
2. IAC SB GMCP "room.info" {"name":"Forest"} IAC SE
   - Forward to GMCP.Handler
3. "You see a forest.\r\n"
   - Publish as :game_text

**Output** (to socket):
```
<<255, 251, 201>>  # IAC WILL GMCP
```

**Events published**:
```elixir
{:event, :gmcp, {:room, %{name: "Forest"}}}
{:event, :game_text, {:text, "You see a forest.\r\n"}}
{:event, :game_text, {:plain_text, "You see a forest."}}
```

## GMCP.Handler

### Responsibilities

1. **Parse GMCP JSON**: Convert JSON strings to Elixir maps
2. **Route by Module**: Handle specific GMCP modules
3. **Update GameState**: Store room, vitals, character data
4. **Publish Events**: Notify subscribers of GMCP data
5. **Send GMCP**: Construct and send GMCP messages to server

### Module Routing

```elixir
def process_gmcp("char.vitals", data) do
  vitals = parse_vitals(data)
  GameState.set_vitals(vitals)
  Bus.publish(:gmcp, {:vitals, vitals})
end

def process_gmcp("room.info", data) do
  room = parse_room(data)
  GameState.set_room(room)
  Bus.publish(:gmcp, {:room, room})
end

def process_gmcp(module, data) do
  # Unknown module - publish generic event
  Bus.publish(:gmcp, {:gmcp, module, data})
end
```

### Error Handling

GMCP.Handler is resilient to errors:

- **Invalid JSON**: Logged, ignored
- **Missing fields**: Default values used
- **Unknown modules**: Published as generic GMCP event

```elixir
case Jason.decode(json) do
  {:ok, data} ->
    process_gmcp(module, data)

  {:error, reason} ->
    Logger.warning("Invalid GMCP JSON: #{inspect(reason)}")
    :ok
end
```

## State.GameState

### Overview

ETS-backed storage for game state extracted from GMCP and text parsing.

### Stored Data

```elixir
%{
  room: %{
    name: "Market Square",
    area: "Bree",
    terrain: "city",
    exits: %{"n" => "1234", "s" => "1235"}
  },
  vitals: %{
    hp: 120,
    max_hp: 150,
    mana: 80,
    max_mana: 100,
    moves: 200,
    max_moves: 250
  },
  character: %{
    name: "MyCharacter",
    level: 10,
    race: "Human",
    class: "Warrior"
  }
}
```

### API

```elixir
# Get current room
room = Mudc.State.GameState.get_room()

# Get vitals
vitals = Mudc.State.GameState.get_vitals()

# Set room (usually from GMCP)
Mudc.State.GameState.set_room(%{name: "Forest", area: "Shire"})

# Set vitals (usually from GMCP)
Mudc.State.GameState.set_vitals(%{hp: 150, max_hp: 150})
```

### ETS Performance

GameState uses ETS with `read_concurrency: true` for fast reads:

- Reads: Direct ETS lookup (~0.1-0.5μs)
- Writes: GenServer call for consistency (~10-50μs)

## MMapper Integration

### Overview

MMapper is a mapping proxy for MUME (Multi-Users in Middle-earth). It sits between client and server, providing automapping and navigation.

**Connection Flow**:
```
Mudc ←→ MMapper (localhost:4242) ←→ MUME Server (mume.org:4242)
```

### MMapper Protocol

MMapper uses XML-based protocol for map data:

```xml
<room>
  <name>Market Square</name>
  <description>You see a fountain.</description>
  <exits>n s e w</exits>
</room>
```

### MMapper Configuration

**config.toml**:
```toml
[connection]
host = "localhost"
port = 4242  # MMapper default port
```

**MMapper Setup**:
1. Start MMapper
2. Configure MMapper to connect to MUME server
3. Start Mudc and connect to localhost:4242

### Benefits

- **Automapping**: MMapper builds map as you explore
- **Pathfinding**: MMapper can navigate for you
- **Speedwalking**: Send movement commands in bulk
- **Synchronization**: Map stays in sync with your location

## Testing

### Testing Telnet Parsing

```elixir
defmodule TelnetTest do
  use ExUnit.Case

  test "parses IAC WILL GMCP" do
    data = <<255, 251, 201>>  # IAC WILL GMCP
    assert Dispatcher.parse_telnet(data) == {:will, 201}
  end

  test "strips ANSI codes" do
    text = "\e[32mGreen\e[0m"
    assert Dispatcher.strip_ansi(text) == "Green"
  end
end
```

### Testing GMCP Parsing

```elixir
defmodule GMCPTest do
  use ExUnit.Case

  test "parses char.vitals" do
    json = ~s({"hp": 120, "max_hp": 150})
    assert GMCP.Handler.parse_vitals(json) == %{hp: 120, max_hp: 150}
  end

  test "handles invalid JSON" do
    json = "{invalid"
    assert GMCP.Handler.process_gmcp("char.vitals", json) == :error
  end
end
```

### Integration Testing

```elixir
test "GMCP flow end-to-end" do
  # Subscribe to events
  Mudc.Events.Bus.subscribe(:gmcp)

  # Simulate GMCP from server
  gmcp_data = <<255, 250, 201, "char.vitals", 32, ~s({"hp":120,"max_hp":150}), 255, 240>>
  Dispatcher.process_data(gmcp_data)

  # Assert event published
  assert_receive {:event, :gmcp, {:vitals, %{hp: 120, max_hp: 150}}}
end
```

## Debugging

### Telnet Packet Inspection

```elixir
# In iex, enable telnet logging
Logger.configure(level: :debug)

# Connect and watch logs
Mudc.Network.Connection.connect("localhost", 4242)

# You'll see:
# [debug] Telnet: IAC DO GMCP
# [debug] Telnet: Responding with IAC WILL GMCP
# [debug] GMCP: room.info {"name":"Forest"}
```

### Raw Packet Capture

```elixir
# Intercept socket data
defmodule PacketLogger do
  def log_packet(data) do
    IO.inspect(data, label: "RAW", limit: :infinity, binaries: :as_binaries)
  end
end

# In Socket.handle_info({:tcp, socket, data}, state)
PacketLogger.log_packet(data)
```

### GMCP Message Logging

```elixir
# Subscribe to all GMCP
Mudc.Events.Bus.subscribe(:gmcp)

spawn(fn ->
  Stream.repeatedly(fn ->
    receive do
      {:event, :gmcp, event} ->
        IO.inspect(event, label: "GMCP")
    end
  end)
  |> Stream.run()
end)
```

## Common Issues

### Connection Refused

**Problem**: Can't connect to server

**Solutions**:
- Check host/port in config.toml
- Verify server is running
- Check firewall rules
- Try telnet command: `telnet localhost 4242`

### No GMCP Data

**Problem**: Connected but not receiving GMCP

**Solutions**:
- Check server supports GMCP
- Verify IAC WILL GMCP was sent
- Enable GMCP modules: `send_gmcp("core.hello", %{client: "Mudc"})`
- Check server requires specific GMCP modules to be enabled

### Garbled Text

**Problem**: Text has weird characters

**Solutions**:
- Server is sending Telnet commands mixed with text
- Dispatcher should filter these - check logs
- May need to improve Telnet parser

### Missing Colors

**Problem**: ANSI colors not displaying

**Solutions**:
- Terminal must support ANSI
- Check TERM environment variable: `echo $TERM`
- Try: `export TERM=xterm-256color`

## References

- [RFC 854: Telnet Protocol](https://tools.ietf.org/html/rfc854)
- [GMCP Specification](https://www.gammon.com.au/gmcp)
- [MMapper GitHub](https://github.com/MUME/MMapper)
- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [Telnet Options Registry](https://www.iana.org/assignments/telnet-options/)

## See Also

- [Architecture Documentation](./architecture.md) - System design
- [Event Bus Documentation](./event-bus.md) - Event flow
- [Configuration Documentation](./configuration.md) - Config system
