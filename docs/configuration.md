# Mudc Configuration

## Overview

Mudc uses Lua programs for configuration with support for environment variables and runtime overrides. Configuration is loaded from `~/.config/mudc/config.lua` and watched for changes (instant reload).

## Configuration File Location

Default: `~/.config/mudc/config.lua`

Override with environment variable:
```bash
export MUDC_CONFIG_DIR=/path/to/config
```

## Configuration Precedence

Configuration values are resolved in this order (highest to lowest priority):

1. **Runtime options** (passed to functions)
2. **Environment variables** (prefixed with `MUD_` or `MUDC_`)
3. **Config file** (`config.lua`)
4. **Default values** (hardcoded in code)

Example:
```elixir
# If config.lua has:
# return {
#   connection = {
#     host = "mud.server.com"
#   }
# }

# But environment has:
export MUD_HOST=localhost

# Then connection will use: localhost (env var wins)
```

## Configuration File Format

### Full Example

```toml
# ~/.config/mudc/config.toml

[connection]
host = "localhost"
port = 4242
auto_connect = false
auto_reconnect_delay_ms = 5000
timeout_ms = 5000

[scripting]
script_dir = "~/.config/mudc/scripts"

[ui]
default_screen = "game"
```

### Section: [connection]

Controls TCP connection behavior.

#### host

- **Type**: String
- **Default**: `"localhost"`
- **Env var**: `MUD_HOST`
- **Description**: Hostname or IP address of the MUD server (or MMapper proxy)

Example:
```lua
return {
  connection = {
    host = "mud.server.com"
  }
}
```

```bash
export MUD_HOST=mume.org
```

#### port

- **Type**: Integer
- **Default**: `4242`
- **Env var**: `MUD_PORT`
- **Description**: TCP port number

Default is 4242 for MMapper compatibility. Standard MUD telnet is often 23 or 4000.

Example:
```lua
return {
  connection = {
    port = 4242
  }
}
```

```bash
export MUD_PORT=23
```

#### auto_connect

- **Type**: Boolean
- **Default**: `false`
- **Description**: Automatically connect on application startup

Useful for development or when always connecting to same server.

Example:
```lua
return {
  connection = {
    auto_connect = true
  }
}
```

#### auto_reconnect_delay_ms

- **Type**: Integer (milliseconds)
- **Default**: `5000`
- **Description**: Delay before attempting reconnection after disconnect

Only applies if connection was established with auto_connect enabled.

Example:
```lua
return {
  connection = {
    auto_reconnect_delay_ms = 3000  -- 3 seconds
  }
}
```

#### timeout_ms

- **Type**: Integer (milliseconds)
- **Default**: `5000`
- **Description**: TCP connection timeout

How long to wait for connection before giving up.

Example:
```lua
return {
  connection = {
    timeout_ms = 10000  -- 10 seconds for slow connections
  }
}
```

### Section: [scripting]

Controls Lua scripting behavior.

#### script_dir

- **Type**: String (path)
- **Default**: `"~/.config/mudc/scripts"`
- **Description**: Directory containing .lua script files

Scripts are loaded in alphabetical order on startup.

Example:
```lua
return {
  scripting = {
    script_dir = "~/mudc-scripts"
  }
}
```

### Section: [ui]

Controls terminal UI behavior.

#### default_screen

- **Type**: String
- **Default**: `"game"`
- **Options**: `"game"`, `"debug"`, `"info"`
- **Description**: Which screen to show on startup

Example:
```lua
return {
  ui = {
    default_screen = "debug"
  }
}
```

## Environment Variables

### MUD_HOST

Override connection host.

```bash
export MUD_HOST=localhost
mix start
```

### MUD_PORT

Override connection port.

```bash
export MUD_PORT=4242
mix start
```

### MUDC_CONFIG_DIR

Override config directory location.

```bash
export MUDC_CONFIG_DIR=/etc/mudc
mix start
```

### MUD_USER / MUD_PASSWORD

Auto-login credentials (used by AutoLogin component).

```bash
export MUD_USER=mycharacter
export MUD_PASSWORD=secretpass
mix start
```

**Security Warning**: Only use for development. Consider using a password manager or encrypted config for production.

## Programmatic Access

### Reading Configuration

```elixir
# Get entire config
config = Mudc.Config.Manager.get()

# Get section
connection_config = Mudc.Config.Manager.get(:connection)

# Get specific key
host = Mudc.Config.Manager.get(:connection, :host)
# => "localhost"

# Get with default if not set
timeout = Mudc.Config.Manager.get(:connection, :custom_timeout, 1000)
# => 1000 (if :custom_timeout not in config)
```

### Writing Configuration

```elixir
# Set value (writes to ETS, not file)
Mudc.Config.Manager.set(:connection, :host, "newhost.com")

# Set entire section
Mudc.Config.Manager.set(:connection, %{host: "newhost.com", port: 4000})
```

**Note**: `set/2` and `set/3` update the in-memory ETS table but **do not** write to `config.lua`. To persist changes, manually edit the file or implement a save function.

### Reloading Configuration

Configuration is automatically reloaded when `config.lua` changes (using FileSystem watcher). You can also trigger manual reload:

```elixir
Mudc.Config.Manager.reload()
```

This will:
1. Re-execute config.lua
2. Re-apply defaults for missing keys
3. Update ETS table
4. Publish `:config_reloaded` event on Event Bus

## Configuration Events

Subscribe to config changes:

```elixir
Mudc.Events.Bus.subscribe(:config)

# Later...
receive do
  {:event, :config, :config_reloaded} ->
    IO.puts("Config was reloaded!")
end
```

## Default Values

If a key is not set in config.toml, defaults are used:

```elixir
@defaults %{
  connection: %{
    host: "localhost",
    port: 4242,
    auto_connect: false,
    auto_reconnect_delay_ms: 5000,
    timeout_ms: 5000
  },
  scripting: %{
    script_dir: "~/.config/mudc/scripts"
  },
  ui: %{
    default_screen: "game"
  }
}
```

## Performance

### ETS-Backed Reads

Configuration reads use direct ETS lookups (no GenServer call):

```elixir
# Fast: direct ETS read (~0.1-0.5μs)
host = Mudc.Config.Manager.get(:connection, :host)

# Slow: GenServer call (~10-50μs) - only for writes
Mudc.Config.Manager.set(:connection, :host, "newhost")
```

This makes config reads 10-100x faster than GenServer-based approaches.

### File Watching

Config file is monitored with FileSystem (inotify on Linux, FSEvents on macOS):
- Changes detected instantly (no polling)
- Sub-second reload time
- Minimal CPU usage

## Troubleshooting

### Config not loading

Check file location:
```elixir
iex> Mudc.Config.Manager.config_path()
"/home/user/.config/mudc/config.toml"
```

Verify file exists and is readable:
```bash
ls -la ~/.config/mudc/config.toml
```

### Environment variables not working

Ensure correct prefix:
- Connection settings: `MUD_HOST`, `MUD_PORT`
- Config directory: `MUDC_CONFIG_DIR`

Check if variable is set:
```bash
echo $MUD_HOST
```

### Changes not taking effect

If you modified config.toml but changes aren't reflected:

1. Check logs for reload confirmation
2. Verify FileSystem watcher is running
3. Try manual reload: `Mudc.Config.Manager.reload()`

### Auto-connect not working

Verify in config.toml:
```toml
[connection]
auto_connect = true
host = "localhost"  # Must have valid host/port
port = 4242
```

Check logs on startup for connection attempts.

## Examples

### Development Setup

```toml
# ~/.config/mudc/config.toml
[connection]
host = "localhost"
port = 4242
auto_connect = true
auto_reconnect_delay_ms = 2000

[scripting]
script_dir = "~/dev/mudc-scripts"

[ui]
default_screen = "debug"
```

### Production Setup

```toml
# ~/.config/mudc/config.toml
[connection]
host = "mume.org"
port = 4242
auto_connect = false
timeout_ms = 10000

[scripting]
script_dir = "~/.config/mudc/scripts"
```

### Testing Setup

```elixir
# In test files
setup do
  # Override config for tests
  Mudc.Config.Manager.set(:connection, %{
    host: "localhost",
    port: 9999,
    timeout_ms: 100
  })

  on_exit(fn ->
    Mudc.Config.Manager.reload()  # Restore from file
  end)
end
```

## Best Practices

1. **Keep secrets out of config.toml**
   - Use environment variables for passwords
   - Consider encrypted credential storage

2. **Use auto_connect sparingly**
   - Helpful for development
   - Annoying for production (might connect when you don't want)

3. **Set reasonable timeouts**
   - Too short: fails on slow connections
   - Too long: user waits unnecessarily

4. **Organize scripts by purpose**
   ```
   ~/.config/mudc/scripts/
   ├── 01-core.lua       # Load first (prefix with number)
   ├── 02-triggers.lua
   ├── 03-aliases.lua
   └── 99-custom.lua     # Load last
   ```

5. **Version control your config**
   ```bash
   cd ~/.config/mudc
   git init
   git add config.toml
   git commit -m "Initial config"
   ```

## Migration Guide

### From Mudc v1 (pre-refactor)

If you used old config format:

**Old** (v1):
```elixir
# In code
@default_port 23
```

**New** (v2):
```toml
# In config.toml
[connection]
port = 4242  # Changed to 4242 for MMapper
```

### From Other MUD Clients

#### From Tintin++

Tintin++ uses `#session name host port`:

```tintin
#session mume mume.org 4242
```

Mudc equivalent:
```toml
[connection]
host = "mume.org"
port = 4242
```

#### From Mudlet

Mudlet stores profiles. For Mudc:

1. Export Mudlet triggers/aliases to Lua
2. Place in `~/.config/mudc/scripts/`
3. Adapt to Mudc API (see scripting docs)

## See Also

- [Architecture Documentation](./architecture.md) - System design
- [Event Bus Documentation](./event-bus.md) - Event topics
- [Scripting Guide](../SCRIPTING.md) - Lua scripting API
