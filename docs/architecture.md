# Mudc Architecture

## Overview

Mudc is a MUD (Multi-User Dungeon) client built with Elixir/OTP, designed for robustness, modularity, and crash recovery. The architecture follows OTP best practices with proper supervision strategies, process isolation, and separation of concerns.

## System Design Goals

- **Fault Tolerance**: Process crashes don't lose critical state
- **Modularity**: Clear separation between components
- **Performance**: ETS-backed reads, efficient config management
- **Maintainability**: Small, focused modules with single responsibilities

## Supervision Tree

```
Mudc.Supervisor (:one_for_one)
├── Mudc.UI.LogBuffer
│   └── (ETS table for log messages)
│
├── Mudc.Events.Bus
│   └── (Registry-based PubSub)
│
├── Mudc.Config.Manager
│   ├── ETS table (read_concurrency: true)
│   └── FileSystem watcher
│
├── Mudc.Protocol.Supervisor (:rest_for_one)
│   ├── Mudc.Protocol.Dispatcher
│   ├── Mudc.Network.GMCP.Handler
│   └── Mudc.State.GameState
│
├── Mudc.Network.Connection.Manager
│   └── Mudc.Network.Connection.Socket (spawned on connect)
│
├── Mudc.Network.AutoLogin
│
├── Mudc.Scripting.Engine
│   └── (Luerl VM)
│
├── Mudc.Scripting.TriggerManager
│   └── (Trigger patterns/callbacks)
│
├── Mudc.Scripting.AliasManager
│   └── (Command aliases)
│
└── Mudc.Scripting.ScriptLoader
    └── (Loads .lua files)
```

## Component Architecture

### Network Layer

#### Connection.Manager + Connection.Socket

The connection system is split into two processes for better crash recovery:

**Connection.Manager** (GenServer)
- Manages connection lifecycle (connect, disconnect, reconnect)
- Stores connection parameters (host, port, auto_reconnect)
- Supervises Socket worker
- Monitors Socket process for crashes
- If Socket crashes, Manager can spawn new Socket with same params

**Connection.Socket** (GenServer)
- Handles TCP I/O operations only
- Receives data with `active: :once` for backpressure
- Forwards data to Protocol.Dispatcher
- Notifies Manager on socket close/error
- If crashes, connection state (host/port) is preserved in Manager

**Benefits**:
- Socket crashes don't lose connection parameters
- Better separation of concerns (lifecycle vs I/O)
- Easier testing and debugging
- Manager can implement reconnection logic without Socket complexity

**Connection** (Facade)
- Provides backward-compatible API
- Delegates all calls to Connection.Manager
- Keeps existing code working without changes

### Protocol Layer

#### Protocol.Supervisor

Groups protocol-related processes with `:rest_for_one` strategy:

```
Protocol.Supervisor (:rest_for_one)
├── Dispatcher    (if crashes, restart all below)
├── GMCP.Handler  (if crashes, restart GameState)
└── GameState     (if crashes, restart only itself)
```

This ensures consistent protocol state:
- If Dispatcher crashes, all protocol state is reset
- If GMCP.Handler crashes, GameState is also reset (prevents stale GMCP data)
- If GameState crashes alone, Dispatcher and GMCP continue

#### Protocol.Dispatcher

Routes Telnet protocol data:
- Parses Telnet commands (IAC sequences)
- Handles GMCP subnegotiation
- Strips ANSI codes for trigger matching
- Publishes events to Event Bus

#### GMCP.Handler

Processes GMCP (Generic MUD Communication Protocol) messages:
- Parses JSON payloads
- Updates GameState
- Publishes GMCP events

#### GameState

ETS-backed game state storage:
- Room info, character stats, vitals
- Fast concurrent reads
- GenServer for consistent updates

### Configuration Layer

#### Config.Manager

High-performance configuration management:

**ETS-Backed Reads**:
- `get/1`, `get/2` do direct ETS lookups (no GenServer call)
- 10-100x faster than GenServer-based config
- `read_concurrency: true` for lock-free reads

**FileSystem Watcher**:
- Monitors `~/.config/mudc/config.lua` for changes
- Instant reload on file modification (no 5-second polling)
- Publishes `:config_reloaded` event

**API**:
```elixir
# Fast ETS reads (no GenServer call)
Config.get(:connection, :host)

# Write operations still use GenServer
Config.set(:connection, :host, "localhost")
```

### Scripting Layer

The scripting system is split into four isolated processes:

#### Scripting.Engine

Manages only the Luerl VM state:
- Evaluates Lua code
- Calls Lua functions by reference
- If VM crashes, triggers/aliases are preserved

#### Scripting.TriggerManager

Pattern matching for triggers:
- Stores trigger registrations (pattern, callback)
- Subscribes to `:game_text` events
- Matches patterns and calls Engine.call_function
- Survives VM crashes

#### Scripting.AliasManager

Command alias expansion:
- Stores alias registrations (name, callback)
- Expands user commands before sending
- Survives VM crashes

#### Scripting.ScriptLoader

Script file management:
- Loads .lua files from `~/.config/mudc/scripts/`
- Handles reload logic
- Independent from VM crashes

**Benefits**:
- VM crash doesn't lose trigger/alias definitions
- Better isolation and testability
- Triggers/aliases can be reloaded without restarting VM
- Easier to debug script issues

### UI Layer

#### UI.App

Main terminal UI application (508 lines, down from 817):
- Built with TermUI.Elm (Elm-like architecture)
- Manages screen state, input, rendering
- Delegates rendering to screen modules

#### Screen Modules

Specialized screen renderers:
- **GameScreen**: ANSI text viewport, vitals, scrolling
- **DebugScreen**: Debug log with dog ASCII art
- **InfoScreen**: Cat ASCII art

Each screen has:
- `ScrollState` for consistent scroll behavior
- Independent rendering logic
- Own viewport calculations

**Benefits**:
- Eliminated 39+ occurrences of duplicated scroll logic
- Each screen is self-contained
- Easier to add new screens
- Reduced UI.App complexity by 38%

### Event Bus

#### Events.Bus

Registry-based PubSub system:
- Topic-based subscriptions
- Async message delivery
- Used for cross-component communication

**Event Topics**:
- `:connection` - Connection state changes
- `:game_text` - Raw and processed game text
- `:gmcp` - GMCP messages
- `:config` - Config reload notifications
- `:vitals` - Character vitals updates

## Crash Recovery Scenarios

### Socket Crashes

1. Socket process exits unexpectedly
2. Connection.Manager receives `:DOWN` message
3. Manager marks connection as disconnected
4. If `auto_reconnect` is enabled:
   - Manager waits configured delay
   - Spawns new Socket with preserved host/port
   - Reconnects automatically

**User Impact**: Minimal - connection state preserved, auto-reconnect works

### Dispatcher Crashes

1. Protocol.Dispatcher process exits
2. Protocol.Supervisor restarts Dispatcher, GMCP.Handler, and GameState
3. All protocol state is reset to consistent initial state

**User Impact**: Protocol state cleared, connection continues

### VM Crashes

1. Scripting.Engine process exits
2. VM state is lost
3. TriggerManager and AliasManager are unaffected
4. Engine restarts with fresh VM
5. ScriptLoader reloads all .lua files
6. Triggers and aliases are re-registered in new VM

**User Impact**: Brief interruption, triggers/aliases automatically restored

### Config.Manager Crashes

1. Config.Manager process exits
2. ETS table is lost (owned by Manager)
3. Supervisor restarts Manager
4. Config is reloaded from disk
5. FileSystem watcher is reattached

**User Impact**: Brief interruption, config restored from file

## Performance Characteristics

### Configuration Reads

- **Before**: GenServer call (~10-50μs per read)
- **After**: Direct ETS lookup (~0.1-0.5μs per read)
- **Improvement**: 10-100x faster

### Config Reload

- **Before**: 5-second polling loop
- **After**: Instant (inotify-based)
- **Improvement**: Sub-second response to config changes

### UI Complexity

- **Before**: 817 lines, 39+ scroll duplications
- **After**: 508 lines, zero duplication
- **Improvement**: 38% reduction, better maintainability

## Design Patterns

### Facade Pattern

`Mudc.Network.Connection` is a facade over `Connection.Manager`:
- Provides stable public API
- Delegates to actual implementation
- Allows internal refactoring without breaking clients

### Split Worker Pattern

Connection and Scripting use split worker pattern:
- **Manager**: Lifecycle, state, supervision
- **Worker**: Actual I/O or computation
- Worker crashes don't lose manager state

### ETS for Fast Reads

Config.Manager and GameState use ETS for performance:
- Direct reads bypass GenServer bottleneck
- `read_concurrency: true` for lock-free access
- GenServer only for writes (consistency)

### Supervision Strategies

- **:one_for_one** (main supervisor): Independent components
- **:rest_for_one** (protocol): Dependent chain (Dispatcher → GMCP → GameState)

## Testing Strategy

### Unit Tests

Each module has focused unit tests:
- Pure functions tested in isolation
- GenServer callbacks tested with mock state
- No external dependencies

### Integration Tests

Critical paths tested end-to-end:
- Connection flow (connect → send → receive → disconnect)
- Protocol parsing (Telnet → ANSI → events)
- Config reload (file change → reload → event)
- Script execution (load → trigger → callback)

### Property Tests

For parsers and protocol handlers:
- Telnet parser handles all IAC sequences
- GMCP parser handles malformed JSON
- ANSI stripper preserves text content

## Future Enhancements

### Multiple Connections

Current design supports single connection. To support multiple:
- Use DynamicSupervisor for Connection.Manager instances
- Name processes with connection ID
- Update UI to handle multiple game screens

### Plugin System

Add dynamic plugin loading:
- Define behavior for plugins
- Load plugins from `~/.config/mudc/plugins/`
- Plugins subscribe to events and provide commands

### MMapper Integration

Integrate with MMapper for automapping:
- Implement MMapper XML protocol
- Add map window to UI
- Sync room data with GameState

## References

- [OTP Design Principles](https://www.erlang.org/doc/design_principles/users_guide.html)
- [Elixir GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)
- [TermUI.Elm Documentation](https://hexdocs.pm/term_ui/)
- [Telnet Protocol (RFC 854)](https://tools.ietf.org/html/rfc854)
- [GMCP Specification](https://www.gammon.com.au/gmcp)
