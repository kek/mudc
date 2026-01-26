# Event Bus Documentation

## Overview

Mudc uses a Registry-based PubSub system (`Mudc.Events.Bus`) for decoupled communication between components. This enables:
- Loose coupling between modules
- Easy extension with new features
- Testability through event observation
- Reactive programming patterns

## Architecture

The Event Bus is implemented using Elixir's `Registry` with the following characteristics:

- **Topic-based**: Subscribe to specific event topics
- **Asynchronous**: Non-blocking event delivery
- **Process-local**: Subscribers receive events in their own process
- **No message loss**: Messages delivered to all subscribers at publish time

## API

### Publishing Events

```elixir
# Publish event on a topic
Mudc.Events.Bus.publish(topic, event)

# Examples
Mudc.Events.Bus.publish(:connection, :connected)
Mudc.Events.Bus.publish(:game_text, {:text, "You see a monster"})
Mudc.Events.Bus.publish(:gmcp, {:room, %{name: "Market Square"}})
```

### Subscribing to Events

```elixir
# Subscribe to a topic
Mudc.Events.Bus.subscribe(topic)

# Examples
Mudc.Events.Bus.subscribe(:connection)
Mudc.Events.Bus.subscribe(:game_text)
Mudc.Events.Bus.subscribe(:gmcp)

# Receive events in your process
receive do
  {:event, topic, event_data} ->
    IO.puts("Received: #{inspect(event_data)}")
end
```

### Unsubscribing

```elixir
# Unsubscribe from a topic
Mudc.Events.Bus.unsubscribe(topic)
```

Subscriptions are automatically removed when the subscriber process exits.

## Event Topics

### :connection

Connection state changes and errors.

**Publishers**: Connection.Manager, Connection.Socket

**Events**:

```elixir
# Successfully connected
{:connected, host, port}
# host: charlist or string
# port: integer

# Disconnected (clean or unexpected)
:disconnected

# Connection error
{:error, reason}
# reason: atom or string describing error
```

**Example Usage**:

```elixir
# Monitor connection status
Mudc.Events.Bus.subscribe(:connection)

receive do
  {:event, :connection, {:connected, host, port}} ->
    IO.puts("Connected to #{host}:#{port}")

  {:event, :connection, :disconnected} ->
    IO.puts("Connection closed")

  {:event, :connection, {:error, reason}} ->
    IO.puts("Connection error: #{inspect(reason)}")
end
```

### :game_text

Game text from the MUD server.

**Publishers**: Protocol.Dispatcher

**Events**:

```elixir
# Raw ANSI text (with color codes)
{:text, ansi_string}

# Plain text (ANSI stripped, for trigger matching)
{:plain_text, plain_string}
```

**Example Usage**:

```elixir
# Trigger system subscribes to game text
Mudc.Events.Bus.subscribe(:game_text)

receive do
  {:event, :game_text, {:text, ansi_text}} ->
    # Display with colors
    IO.puts(ansi_text)

  {:event, :game_text, {:plain_text, plain_text}} ->
    # Match triggers without ANSI interference
    if String.contains?(plain_text, "attacks you") do
      Mudc.Network.Connection.send_command("flee")
    end
end
```

### :gmcp

GMCP (Generic MUD Communication Protocol) messages.

**Publishers**: Network.GMCP.Handler

**Events**:

```elixir
# Room information
{:room, room_data}
# room_data: map with keys like :name, :area, :exits

# Character information
{:char, char_data}
# char_data: map with character stats

# Character vitals (HP, mana, etc.)
{:vitals, vitals_data}
# vitals_data: map with current/max values

# Generic GMCP message
{:gmcp, module, data}
# module: string like "room.info"
# data: parsed JSON data
```

**Example Usage**:

```elixir
# Update UI with character vitals
Mudc.Events.Bus.subscribe(:gmcp)

receive do
  {:event, :gmcp, {:vitals, %{hp: hp, max_hp: max_hp}}} ->
    IO.puts("HP: #{hp}/#{max_hp}")

  {:event, :gmcp, {:room, %{name: name}}} ->
    IO.puts("Entered: #{name}")
end
```

### :config

Configuration reload notifications.

**Publishers**: Config.Manager

**Events**:

```elixir
# Configuration file reloaded
:config_reloaded
```

**Example Usage**:

```elixir
# React to config changes
Mudc.Events.Bus.subscribe(:config)

receive do
  {:event, :config, :config_reloaded} ->
    # Reload scripts, update settings, etc.
    new_host = Mudc.Config.Manager.get(:connection, :host)
    IO.puts("Config reloaded, host is now: #{new_host}")
end
```

### :vitals

Character vitals updates (HP, mana, movement, etc.).

**Publishers**: State.GameState

**Events**:

```elixir
# Vitals changed
{:vitals, vitals_map}
# vitals_map: %{hp: int, max_hp: int, mana: int, max_mana: int, ...}
```

**Example Usage**:

```elixir
# UI subscribes to display vitals bar
Mudc.Events.Bus.subscribe(:vitals)

receive do
  {:event, :vitals, vitals} ->
    hp_percent = vitals.hp / vitals.max_hp * 100
    render_vitals_bar(hp_percent)
end
```

## Event Flow Examples

### Connection Flow

```
User Action: Mudc.Network.Connection.connect("localhost", 4242)
    ↓
Connection.Manager starts Connection.Socket
    ↓
Socket connects to TCP server
    ↓
Events.Bus.publish(:connection, {:connected, "localhost", 4242})
    ↓
Subscribers notified:
  - UI.App updates status display
  - AutoLogin sends credentials
```

### Game Text Flow

```
TCP socket receives data: "\e[32mYou see a monster\e[0m\n"
    ↓
Socket forwards to Protocol.Dispatcher
    ↓
Dispatcher:
  - Parses Telnet sequences
  - Publishes {:text, "\e[32mYou see a monster\e[0m"}
  - Strips ANSI
  - Publishes {:plain_text, "You see a monster"}
    ↓
Subscribers notified:
  - UI.App displays ANSI text
  - TriggerManager matches plain text
  - GameState updates room description
```

### GMCP Flow

```
Socket receives: IAC SB GMCP "room.info" {"name": "Forest"} IAC SE
    ↓
Protocol.Dispatcher extracts GMCP data
    ↓
GMCP.Handler parses JSON and publishes:
  - {:gmcp, {:room, %{name: "Forest"}}}
    ↓
Subscribers notified:
  - GameState updates room info
  - UI.App updates room display
  - Script callbacks triggered
```

### Config Reload Flow

```
User edits: ~/.config/mudc/config.toml
    ↓
FileSystem watcher detects change
    ↓
Config.Manager reloads config file
    ↓
Events.Bus.publish(:config, :config_reloaded)
    ↓
Subscribers notified:
  - ScriptLoader reloads scripts
  - UI.App refreshes display
  - Connection updates timeout values
```

## Subscription Patterns

### Basic Subscription

```elixir
defmodule MySubscriber do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    # Subscribe on init
    Mudc.Events.Bus.subscribe(:game_text)
    {:ok, %{}}
  end

  def handle_info({:event, :game_text, {:text, text}}, state) do
    IO.puts("Received: #{text}")
    {:noreply, state}
  end
end
```

### Multiple Topic Subscription

```elixir
def init(_opts) do
  Mudc.Events.Bus.subscribe(:connection)
  Mudc.Events.Bus.subscribe(:game_text)
  Mudc.Events.Bus.subscribe(:gmcp)
  {:ok, %{}}
end

def handle_info({:event, topic, event}, state) do
  handle_event(topic, event, state)
end

defp handle_event(:connection, {:connected, _, _}, state) do
  {:noreply, %{state | connected: true}}
end

defp handle_event(:game_text, {:text, text}, state) do
  # Process text
  {:noreply, state}
end

defp handle_event(:gmcp, gmcp_event, state) do
  # Process GMCP
  {:noreply, state}
end
```

### Filtered Subscription

```elixir
def handle_info({:event, :game_text, {:plain_text, text}}, state) do
  if String.contains?(text, "attack") do
    # Only process attack-related messages
    handle_attack(text)
  end
  {:noreply, state}
end
```

### Temporary Subscription

```elixir
def wait_for_connection do
  Mudc.Events.Bus.subscribe(:connection)

  receive do
    {:event, :connection, {:connected, _, _}} ->
      Mudc.Events.Bus.unsubscribe(:connection)
      :connected
  after
    5000 ->
      Mudc.Events.Bus.unsubscribe(:connection)
      {:error, :timeout}
  end
end
```

## Testing with Events

Events make testing easier by allowing observation of system behavior:

### Testing Event Publishing

```elixir
defmodule ConnectionTest do
  use ExUnit.Case

  test "publishes connected event" do
    # Subscribe to connection events
    Mudc.Events.Bus.subscribe(:connection)

    # Trigger connection
    Mudc.Network.Connection.connect("localhost", 4242)

    # Assert event received
    assert_receive {:event, :connection, {:connected, "localhost", 4242}}
  end
end
```

### Testing Event Handling

```elixir
test "trigger fires on text match" do
  # Setup trigger
  Mudc.Scripting.TriggerManager.register("monster", fn _text ->
    send(self(), :trigger_fired)
  end)

  # Simulate game text
  Mudc.Events.Bus.publish(:game_text, {:plain_text, "You see a monster"})

  # Assert trigger executed
  assert_receive :trigger_fired
end
```

## Performance Considerations

### Event Delivery

- Events are delivered **synchronously** to all subscribers
- Each subscriber receives event in separate message
- No blocking: if subscriber is busy, message queues

### Subscriber Isolation

- Slow subscriber doesn't block publisher
- Crashed subscriber doesn't affect others
- Subscriber mailbox can grow if processing is slow

### Best Practices

1. **Keep handlers fast**: Process events quickly or delegate to async task
2. **Avoid blocking**: Don't do heavy computation in event handler
3. **Monitor mailbox**: If subscriber is slow, mailbox grows
4. **Unsubscribe when done**: Clean up to avoid memory leaks

```elixir
# Good: Quick processing
def handle_info({:event, :game_text, {:text, text}}, state) do
  # Fast: update state
  {:noreply, %{state | last_text: text}}
end

# Bad: Slow processing
def handle_info({:event, :game_text, {:text, text}}, state) do
  # Slow: database write
  Database.insert(text)  # Blocks handler
  {:noreply, state}
end

# Good: Async processing
def handle_info({:event, :game_text, {:text, text}}, state) do
  # Fast: spawn async task
  Task.start(fn -> Database.insert(text) end)
  {:noreply, state}
end
```

## Common Patterns

### State Aggregation

```elixir
# Aggregate multiple events into state
defmodule GameState do
  def init(_) do
    Mudc.Events.Bus.subscribe(:gmcp)
    {:ok, %{room: nil, vitals: nil}}
  end

  def handle_info({:event, :gmcp, {:room, room}}, state) do
    {:noreply, %{state | room: room}}
  end

  def handle_info({:event, :gmcp, {:vitals, vitals}}, state) do
    {:noreply, %{state | vitals: vitals}}
  end
end
```

### Event Transformation

```elixir
# Transform and republish events
defmodule TextProcessor do
  def init(_) do
    Mudc.Events.Bus.subscribe(:game_text)
    {:ok, %{}}
  end

  def handle_info({:event, :game_text, {:text, text}}, state) do
    # Extract structured data
    if extracted = extract_damage(text) do
      Mudc.Events.Bus.publish(:combat, {:damage, extracted})
    end
    {:noreply, state}
  end
end
```

### Event Filtering

```elixir
# Subscribe to multiple topics, filter by criteria
defmodule Logger do
  def init(_) do
    Mudc.Events.Bus.subscribe(:connection)
    Mudc.Events.Bus.subscribe(:game_text)
    {:ok, %{filter: :all}}
  end

  def handle_info({:event, topic, event}, %{filter: :all} = state) do
    log_event(topic, event)
    {:noreply, state}
  end

  def handle_info({:event, :connection, event}, %{filter: :connection} = state) do
    log_event(:connection, event)
    {:noreply, state}
  end

  def handle_info({:event, _, _}, state) do
    # Filtered out
    {:noreply, state}
  end
end
```

## Debugging Events

### Observing All Events

```elixir
# Spawn observer process
spawn(fn ->
  Mudc.Events.Bus.subscribe(:connection)
  Mudc.Events.Bus.subscribe(:game_text)
  Mudc.Events.Bus.subscribe(:gmcp)

  Stream.repeatedly(fn ->
    receive do
      {:event, topic, event} ->
        IO.inspect({topic, event}, label: "EVENT")
    end
  end)
  |> Stream.run()
end)
```

### Event Logging

```elixir
defmodule EventLogger do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    topics = [:connection, :game_text, :gmcp, :config, :vitals]
    Enum.each(topics, &Mudc.Events.Bus.subscribe/1)
    {:ok, %{}}
  end

  def handle_info({:event, topic, event}, state) do
    Logger.debug("Event[#{topic}]: #{inspect(event)}")
    {:noreply, state}
  end
end
```

## See Also

- [Architecture Documentation](./architecture.md) - System design
- [Configuration Documentation](./configuration.md) - Config system
- [Protocol Documentation](./protocol.md) - Telnet and GMCP
