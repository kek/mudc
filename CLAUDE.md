# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mudc is a MUD (Multi-User Dungeon) client written in Elixir/OTP. It aims to provide functionality similar to Mudlet, Tinyfugue, and Tintin++.

Key features:
- Lua-based configuration (using Luerl)
- Hot-reload configuration with FileSystem watcher
- MMapper integration (https://github.com/MUME/MMapper)
- Telnet protocol support
- GMCP (Generic MUD Communication Protocol)
- Lua scripting engine via Luerl

UI toolkit: pcharbon70/term_ui

## Build and Development Commands

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Run a single test file
mix test test/mudc_test.exs

# Run a specific test by line number
mix test test/mudc_test.exs:5

# Format code
mix format

# Start interactive shell with app loaded
iex -S mix

# Start Mudc with remote REPL support (recommended)
mix start

# Connect to running instance from another terminal
mix connect
```

## Remote REPL Access

For debugging and inspection, you can connect to a running Mudc instance from a separate terminal:

```bash
# Terminal 1: Start Mudc with named node
mix start

# Terminal 2: Connect to the running instance
mix connect
```

`mix start` automatically starts distributed Erlang using `:net_kernel.start/1` and configures
the secure cookie. You can also use `./start.sh` if you prefer the shell script approach.

Once connected, you have full access to the running application:

```elixir
# Check connection status
Mudc.status()

# Send commands
Mudc.send("look")

# Inspect state
:sys.get_state(Mudc.Network.Connection)

# View logs
Mudc.UI.LogBuffer.get_logs()

# Hot reload code
recompile()
```

See `docs/remote-repl.md` for detailed documentation.

## Cookie Management

Erlang distribution cookies are automatically generated and stored in `~/.config/mudc/.erlang.cookie`.

The cookie is:
- Generated on first `mix start`
- Secured with 0600 file permissions
- Reused on subsequent runs
- 32 bytes of cryptographically secure random data

To regenerate if needed:
```bash
rm ~/.config/mudc/.erlang.cookie
mix start
```

Or programmatically:
```elixir
iex> Mudc.Config.CookieManager.regenerate_cookie()
```

## Configuration

Mudc uses Lua programs for configuration instead of static files like TOML or YAML. This provides:

1. **Dynamic Configuration**: Use Lua logic, variables, and conditionals
2. **Environment Integration**: Read from `os.getenv()` in config
3. **Hot Reload**: Changes detected instantly via FileSystem watcher
4. **Computed Values**: Build config programmatically

Configuration file location: `~/.config/mudc/config.lua`

The config file path can be overridden with the `MUDC_CONFIG_PATH` environment variable:
```bash
MUDC_CONFIG_PATH=/custom/path/config.lua mix start
```

Example config:
```lua
local is_dev = os.getenv("ENV") == "development"

return {
  connection = {
    host = os.getenv("MUD_HOST") or "localhost",
    port = 4242,
    auto_connect = is_dev,
    timeout_ms = 5000
  },
  ui = {
    default_screen = is_dev and "debug" or "game"
  }
}
```

See `config.lua.example` for a full annotated example.

## Architecture

Standard Elixir/OTP application structure:
- `lib/mudc.ex` - Main module
- `lib/mudc/application.ex` - OTP Application with supervisor (`:one_for_one` strategy)
- `lib/mudc/config/manager.ex` - Lua configuration loader using Luerl
- `test/` - ExUnit tests with doctest support
