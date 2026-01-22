# MUDC - Multi-User Dungeon Client

A Telnet-based MUD (Multi-User Dungeon) client built in Elixir with an interactive terminal UI.

## Features

- **Telnet Protocol Support**: Full implementation of Telnet protocol with IAC command handling
- **Terminal UI**: Clean, responsive terminal interface built with TermUI.Elm
- **Command History**: Navigate previous commands with Up/Down arrows
- **Connection Management**: Auto-reconnect on connection failures via supervision
- **MUME/MMapper Compatible**: Configured for connecting to MMapper proxy for MUME

## Architecture

- **Mudc.Telnet.Client**: GenServer managing TCP connection and Telnet protocol
- **Mudc.Telnet.Protocol**: Telnet IAC sequence encoding/decoding
- **Mudc.UI.Terminal**: TermUI.Elm-based interactive interface
- **OTP Supervision**: Fault-tolerant design with automatic restart

## Installation & Setup

### Prerequisites

- Elixir ~> 1.19
- Erlang/OTP 27
- WSL2 (if connecting to Windows host)
- MMapper running on Windows (or another Telnet MUD server)

### Install Dependencies

```bash
mix deps.get
mix compile
```

## Usage

### Start the Client

```bash
mix mudc.start
```

This will launch the terminal UI and automatically connect to MMapper at `172.24.0.1:4242`.

### Controls

- **Type commands** and press `Enter` to send them to the MUD
- **Up/Down arrows** to navigate command history
- **Ctrl+C** or **Ctrl+D** to quit
- Type `quit` or `exit` to disconnect and quit

### Example Session

```
╔═══════════════════════════════════════════════════════════╗
║          MUDC - Multi-User Dungeon Client                ║
║                    v0.1.0                                 ║
╚═══════════════════════════════════════════════════════════╝

Connecting to MMapper at 172.24.0.1:4242...
┌─ Status: Connected ──────────────────────────────────────┐

Connected successfully!

> look
> north
> inventory
```

## Configuration

### Connection Settings

Default connection settings are in `lib/mudc/telnet/connection_config.ex`:

```elixir
defstruct host: "172.24.0.1",  # WSL to Windows host IP
          port: 4242,           # MMapper default port
          timeout: 5000,
          active: true
```

To connect to a different server, you can modify these defaults or pass options when starting the client programmatically.

### Programmatic Usage

```elixir
# Start the Telnet client directly
{:ok, pid} = Mudc.Telnet.Client.start_link(
  ui_pid: self(),
  host: "localhost",
  port: 4000
)

# Send commands
Mudc.Telnet.Client.send_command("look")

# Check status
Mudc.Telnet.Client.status()
```

## Testing

Run the full test suite:

```bash
mix test
```

Run specific test files:

```bash
mix test test/mudc/telnet/protocol_test.exs
mix test test/mudc/telnet/client_test.exs
```

### Test Coverage

- **Protocol Tests**: Telnet IAC encoding/decoding, negotiation
- **Client Tests**: Connection config, basic GenServer API
- **23+ tests** with full coverage of protocol handling

## Development

### Code Quality

```bash
# Format code
mix format

# Check formatting
mix format --check-formatted
```

### Interactive Development

```bash
# Start IEx with the application loaded
iex -S mix

# Manually start components
iex> {:ok, client} = Mudc.Telnet.Client.start_link(ui_pid: self())
iex> Mudc.Telnet.Client.send_command("look")
```

## Project Structure

```
lib/
├── mudc.ex                      # Main module
├── mudc/
│   ├── application.ex           # OTP application
│   ├── telnet/
│   │   ├── client.ex           # Telnet TCP client GenServer
│   │   ├── protocol.ex         # Telnet protocol handling
│   │   └── connection_config.ex # Connection configuration
│   └── ui/
│       └── terminal.ex         # Terminal UI (TermUI.Elm)
└── mix/
    └── tasks/
        └── mudc.start.ex       # Mix task to launch client

test/
├── mudc_test.exs
└── mudc/
    └── telnet/
        ├── protocol_test.exs   # Protocol unit tests
        └── client_test.exs     # Client tests
```

## Telnet Protocol Support

Currently implemented:

- **IAC Commands**: WILL, WONT, DO, DONT
- **IAC Escaping**: Literal 255 bytes (IAC IAC)
- **Subnegotiation**: Basic parsing (IAC SB ... IAC SE)
- **Negotiation Strategy**: Reject most options (simple, compatible)

Future enhancements:

- GMCP (Generic MUD Communication Protocol)
- MCCP (MUD Client Compression Protocol)
- Full subnegotiation support for specific options

## UI Features

Current:

- Text output display
- Command input with character-by-character echo
- Connection status indicator
- Command history (up to 100 commands)
- Status bar with connection state

Future enhancements:

- Split panes (output, chat, map)
- ANSI color support
- Scrollback buffer search
- Autocomplete
- Toast notifications
- Status bar with HP/mana/moves

## Troubleshooting

### Connection Fails

If you see "Connection failed: :nxdomain" or ":econnrefused":

1. Check that MMapper is running on Windows
2. Verify the Windows host IP in WSL: `ip route | grep default`
3. Ensure Windows firewall allows connections on port 4242
4. Test connection: `telnet 172.24.0.1 4242`

### WSL Network Issues

If you can't reach the Windows host from WSL:

```bash
# Get Windows host IP
ip route | grep default | awk '{print $3}'

# Test connectivity
ping <windows-ip>
telnet <windows-ip> 4242
```

### UI Not Starting

If TermUI fails to start:

1. Ensure terminal supports ANSI escape codes
2. Try a different terminal emulator (recommended: alacritty, kitty, wezterm)
3. Check terminal size is at least 80x24

## License

Copyright (c) 2025

This project is licensed under the MIT License.

## Contributing

This is a personal project, but suggestions and bug reports are welcome!

## Credits

- Built with [Elixir](https://elixir-lang.org/)
- UI powered by [TermUI](https://hex.pm/packages/term_ui)
- Designed for [MUME](http://mume.org/) via [MMapper](https://github.com/MUME/MMapper)
