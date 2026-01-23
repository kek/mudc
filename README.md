# Mudc

A MUD (Multi-User Dungeon) client for MUME, written in Elixir/OTP.

## Quick Start

```bash
# Install dependencies
mix deps.get

# Run the client
iex -S mix
iex> Mudc.run()
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

### Connection Status

- The top line shows `[CONNECTED]` in green when connected, or `[DISCONNECTED]` in red when not connected
- The bottom status bar shows the current connection state and any error messages

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
