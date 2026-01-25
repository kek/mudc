# Refactoring Opportunities in Mudc

This document outlines refactoring opportunities identified in the Mudc codebase, organized by priority and impact.

## High Priority

### 1. Code Duplication - Host/Port Conversion Logic

**Location:** `lib/mudc/network/connection.ex:199-207`

**Issue:** The `do_connect/2` function has complex charlist conversion logic that could be extracted and reused:

```elixir
defp do_connect(host, port) do
  host_charlist =
    cond do
      is_binary(host) -> String.to_charlist(host)
      is_list(host) -> host
      true -> to_charlist(host)
    end
  # ...
end
```

**Refactoring:** Extract to a reusable helper module `Mudc.Network.Utils`:

```elixir
defmodule Mudc.Network.Utils do
  @moduledoc """
  Utility functions for network operations.
  """
  
  @doc """
  Converts various input types to charlist for :gen_tcp operations.
  """
  def to_charlist(value) when is_binary(value), do: String.to_charlist(value)
  def to_charlist(value) when is_list(value), do: value
  def to_charlist(value), do: Kernel.to_charlist(value)
end
```

**Benefits:**
- Reusable across network modules
- Easier to test in isolation
- Clearer intent

---

### 2. Long Function - UI App Event Handling

**Location:** `lib/mudc/ui/app.ex:130-245`

**Issue:** The `event_to_msg/2` function has 40+ pattern matches for different key events. This makes the function hard to maintain, test, and understand at a glance.

**Refactoring:** Split into logical groups by event type:

```elixir
defp event_to_msg(%Event.Key{} = event, state) do
  handle_key_event(event, state)
end

defp event_to_msg(%Event.Resize{} = event, _state) do
  handle_resize_event(event)
end

# Key event handlers
defp handle_key_event(%Event.Key{key: :enter}, state), do: {:msg, {:send_command, state.input_buffer}}
defp handle_key_event(%Event.Key{key: key, modifiers: [:ctrl]}, _) when key in [:up, :down, :left, :right] do
  handle_ctrl_arrows(key)
end
defp handle_key_event(%Event.Key{key: key, modifiers: [:ctrl]}, _) when key in ["c", "q"], do: {:msg, :quit}
defp handle_key_event(%Event.Key{key: key}, _) when key in [:f3, :f4, :f5], do: handle_function_keys(key)
# ... etc

defp handle_ctrl_arrows(:up), do: {:msg, {:send_command, "north"}}
defp handle_ctrl_arrows(:down), do: {:msg, {:send_command, "south"}}
defp handle_ctrl_arrows(:left), do: {:msg, {:send_command, "west"}}
defp handle_ctrl_arrows(:right), do: {:msg, {:send_command, "east"}}
```

**Benefits:**
- Easier to find and modify specific event handlers
- Better testability of individual handler groups
- Clearer organization and intent

---

## Medium Priority

### 3. Inconsistent Error Handling

**Locations:** Multiple files across the codebase

**Issue:** The codebase has inconsistent error handling patterns:
- `lib/mudc/config/cookie_manager.ex` returns `{:ok, cookie} | {:error, reason}`
- `lib/mudc/network/connection.ex` sometimes returns `:ok | {:error, reason}`
- `lib/mudc/protocol/dispatcher.ex` returns `nil | binary()`

**Refactoring:** Standardize on `{:ok, result} | {:error, reason}` pattern across all public APIs.

**Examples:**

```elixir
# Before (in Protocol.Dispatcher)
def process_data(data) do
  # Returns nil or binary
end

# After
def process_data(data) do
  case do_process(data) do
    nil -> {:ok, :no_response}
    response -> {:ok, response}
  end
end
```

**Benefits:**
- Predictable API surface
- Better composition with `with` statements
- Easier error handling for callers

---

### 4. Duplicate Scroll Logic

**Location:** `lib/mudc/ui/app.ex:358-388`

**Issue:** The scroll handling for game screen and dog screen is nearly identical but duplicated:

```elixir
def update({:scroll, delta}, state) do
  case state.current_screen do
    :game ->
      max_scroll = max(0, length(state.lines) - state.viewport_height)
      new_offset = state.scroll_offset + delta
      new_offset = max(0, min(max_scroll, new_offset))
      auto_scroll = new_offset >= max_scroll
      {%{state | scroll_offset: new_offset, auto_scroll: auto_scroll}, []}

    :dog ->
      # Nearly identical code with different field names...
```

**Refactoring:** Extract scroll logic to a reusable function:

```elixir
defp calculate_scroll(delta, lines, viewport_height, current_offset) do
  max_scroll = max(0, length(lines) - viewport_height)
  new_offset = (current_offset + delta) |> max(0) |> min(max_scroll)
  auto_scroll = new_offset >= max_scroll
  {new_offset, auto_scroll}
end

def update({:scroll, delta}, state) do
  case state.current_screen do
    :game ->
      {new_offset, auto_scroll} = calculate_scroll(
        delta, state.lines, state.viewport_height, state.scroll_offset
      )
      {%{state | scroll_offset: new_offset, auto_scroll: auto_scroll}, []}

    :dog ->
      log_viewport_height = calculate_dog_log_viewport_height(state)
      {new_offset, auto_scroll} = calculate_scroll(
        delta, state.log_lines, log_viewport_height, state.dog_scroll_offset
      )
      {%{state | dog_scroll_offset: new_offset, dog_auto_scroll: auto_scroll}, []}
  end
end
```

**Benefits:**
- Single source of truth for scroll calculations
- Easier to test scroll logic in isolation
- Consistent behavior across screens

---

### 5. Complex Configuration Merging

**Location:** `lib/mudc/config/manager.ex:181-190`

**Issue:** The `merge_config/2` function performs nested map merging with custom logic:

```elixir
defp merge_config(defaults, parsed) do
  Map.merge(defaults, parsed, fn _key, default, parsed_val ->
    if is_map(default) and is_map(parsed_val) do
      Map.merge(default, parsed_val)
    else
      parsed_val
    end
  end)
end
```

**Refactoring:** Extract to a dedicated `Mudc.Config.Merger` module with comprehensive tests, or consider using a library like `deep_merge`:

```elixir
defmodule Mudc.Config.Merger do
  @moduledoc """
  Handles deep merging of configuration maps.
  """
  
  @doc """
  Deep merges two maps, with values from `override` taking precedence.
  
  For nested maps, merges recursively.
  For all other types, uses the override value.
  """
  def deep_merge(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, base_val, override_val ->
      merge_values(base_val, override_val)
    end)
  end
  
  defp merge_values(base, override) when is_map(base) and is_map(override) do
    deep_merge(base, override)
  end
  
  defp merge_values(_base, override), do: override
end
```

**Benefits:**
- Better tested in isolation
- Reusable for other configuration scenarios
- Clearer semantics

---

### 6. God Function - render_debug_logs

**Location:** `lib/mudc/ui/app.ex:635-695`

**Issue:** This 60-line function does too much: calculates layout, formats borders, filters logs, and renders UI components.

**Refactoring:** Break into smaller, focused functions:

```elixir
defp render_debug_logs(state) do
  layout = calculate_debug_layout(state)
  visible_logs = get_visible_logs(state, layout)
  
  stack(:vertical, [
    render_debug_border(:top, state.term_width),
    render_dog_art(),
    render_debug_border(:middle, state.term_width),
    render_log_header(state, visible_logs, layout),
    render_debug_border(:middle, state.term_width),
    render_log_lines(visible_logs),
    render_debug_border(:bottom, state.term_width)
  ])
end

defp calculate_debug_layout(state) do
  dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
  dog_height = dog_lines_count + 4
  log_viewport_height = max(state.term_height - @reserved_lines - dog_height, 5)
  
  %{
    dog_height: dog_height,
    log_viewport_height: log_viewport_height
  }
end

defp get_visible_logs(state, layout) do
  state.log_lines
  |> Enum.drop(state.dog_scroll_offset)
  |> Enum.take(layout.log_viewport_height)
  |> pad_logs(layout.log_viewport_height)
end

defp pad_logs(logs, target_height) do
  logs ++ List.duplicate("", target_height - length(logs))
end

defp render_log_lines(visible_logs) do
  log_elements = Enum.map(visible_logs, &render_log_line/1)
  stack(:vertical, log_elements)
end

defp render_log_line(line) do
  style = log_line_style(line)
  text(line, style)
end

defp log_line_style(line) do
  cond do
    String.contains?(line, "[error]") -> Style.new(fg: :red, attrs: [:bold])
    String.contains?(line, "[warning]") -> Style.new(fg: :yellow)
    String.contains?(line, "[info]") -> Style.new(fg: :green)
    String.contains?(line, "[debug]") -> Style.new(fg: :cyan, attrs: [:dim])
    true -> Style.new(fg: :white)
  end
end
```

**Benefits:**
- Each function has a single, clear responsibility
- Easier to test individual pieces
- More maintainable and readable

---

## Low Priority

### 7. Magic Numbers - UI Reserved Lines

**Location:** `lib/mudc/ui/app.ex:20-21`

**Issue:** The `@reserved_lines` constant is documented with a comment, but the calculation is repeated in multiple places (lines 452, 479).

```elixir
@max_lines 1000
# Reserved lines: header(1) + tabs(1) + vitals(1) + top_border(1) + bottom_border(1) + empty(1) + input(1) + status(1) = 8
@reserved_lines 8
```

**Refactoring:** Create a module or function that makes the calculation explicit and self-documenting:

```elixir
defmodule Mudc.UI.Layout do
  @moduledoc """
  Layout calculations for the Mudc UI.
  """
  
  defstruct header: 1,
            tabs: 1,
            vitals: 1,
            top_border: 1,
            bottom_border: 1,
            spacing: 1,
            input: 1,
            status: 1
  
  @doc """
  Calculate total reserved lines for the UI.
  """
  def reserved_lines(%__MODULE__{} = layout \\ %__MODULE__{}) do
    layout.header + layout.tabs + layout.vitals + 
    layout.top_border + layout.bottom_border + 
    layout.spacing + layout.input + layout.status
  end
  
  @doc """
  Calculate viewport height given terminal height.
  """
  def viewport_height(term_height, layout \\ %__MODULE__{}) do
    max(term_height - reserved_lines(layout), 5)
  end
end
```

**Benefits:**
- Self-documenting code
- Easier to modify layout in the future
- Single source of truth

---

### 8. Hardcoded Telnet Options

**Location:** `lib/mudc/protocol/dispatcher.ex:14-17`

**Issue:** Telnet option constants are duplicated when they already exist in `Mudc.Network.Telnet.Constants`:

```elixir
@opt_gmcp 201
@opt_suppress_go_ahead 3
@opt_echo 1
@opt_terminal_type 24
@opt_window_size 31
```

**Refactoring:** Use the constants from the existing module:

```elixir
# At the top of the module
alias Mudc.Network.Telnet.Constants, as: TC

# In guards, use the function calls or define module attributes from them
@opt_gmcp TC.gmcp()
@opt_suppress_go_ahead TC.suppress_go_ahead()
@opt_echo TC.echo()
@opt_terminal_type TC.terminal_type()
@opt_window_size TC.window_size()
```

**Note:** If Constants module doesn't export these as functions, add them there first.

**Benefits:**
- Single source of truth for protocol constants
- Easier to maintain when protocol changes

---

### 9. Inconsistent Naming Conventions

**Locations:** Multiple files

**Issue:** Private function naming is inconsistent across the codebase:
- `lib/mudc/network/connection.ex` uses `do_connect` (prefix pattern)
- `lib/mudc/config/cookie_manager.ex` uses `generate_and_store_cookie` (descriptive)
- `lib/mudc/protocol/dispatcher.ex` uses `dispatch_event` (verb-noun)

**Refactoring:** Standardize on Elixir convention, which prefers descriptive names for private functions. Reserve `do_*` pattern for when you specifically need to distinguish between public and private implementations of the same concept.

**Examples:**

```elixir
# Good: descriptive names
defp parse_telnet_command(...)
defp calculate_viewport_height(...)
defp merge_configuration_maps(...)

# Good: do_ prefix when there's a public wrapper
def connect(host, port), do: GenServer.call(__MODULE__, {:connect, host, port})
defp do_connect(host, port), do: :gen_tcp.connect(...)

# Avoid: unnecessary do_ prefix
defp do_parse(...) # Just call it parse/1 if there's no public parse/1
```

**Benefits:**
- More consistent codebase
- Easier to understand intent
- Follows community conventions

---

### 10. State Struct Improvements

**Location:** `lib/mudc/ui/app.ex:77-108`

**Issue:** The UI state is a plain map with 15+ keys, making it hard to understand which keys are required and what their types should be.

**Refactoring:** Use a struct with typespecs:

```elixir
defmodule Mudc.UI.App.State do
  @moduledoc """
  State for the Mudc UI application.
  """
  
  @type screen :: :game | :dog | :cat
  
  @type t :: %__MODULE__{
    # Terminal dimensions
    term_width: pos_integer(),
    term_height: pos_integer(),
    viewport_height: pos_integer(),
    
    # Screen selection
    current_screen: screen(),
    
    # Game text
    lines: [String.t()],
    scroll_offset: non_neg_integer(),
    auto_scroll: boolean(),
    
    # Command input
    input_buffer: String.t(),
    history: [String.t()],
    history_index: non_neg_integer() | nil,
    
    # Connection
    connected: boolean(),
    status_message: String.t(),
    
    # GMCP data
    vitals: map(),
    room: map(),
    
    # Debug logs
    log_lines: [String.t()],
    dog_scroll_offset: non_neg_integer(),
    dog_auto_scroll: boolean()
  }
  
  defstruct [
    term_width: 80,
    term_height: 24,
    viewport_height: 16,
    current_screen: :game,
    lines: [],
    scroll_offset: 0,
    auto_scroll: true,
    input_buffer: "",
    history: [],
    history_index: nil,
    connected: false,
    status_message: "",
    vitals: %{},
    room: %{},
    log_lines: [],
    dog_scroll_offset: 0,
    dog_auto_scroll: true
  ]
end
```

Then in the main module:
```elixir
alias Mudc.UI.App.State

def init(_opts) do
  {width, height} = get_terminal_size()
  
  %State{
    term_width: width,
    term_height: height,
    viewport_height: calculate_viewport_height(height),
    lines: [
      "Welcome to Mudc - MUME Client",
      # ...
    ],
    status_message: "Commands: /connect, /disconnect, /quit | ..."
  }
end
```

**Benefits:**
- Compile-time checking of field names
- Clear documentation of state structure
- Better IDE support and tooling
- Default values clearly specified

---

### 11. Connection State Initialization

**Location:** `lib/mudc/network/connection.ex:62-75`

**Issue:** The init function reads from env vars and config, mixing multiple concerns in one place.

**Refactoring:** Extract configuration resolution to dedicated functions:

```elixir
@impl true
def init(opts) do
  config = resolve_connection_config(opts)
  
  state = %__MODULE__{
    socket: nil,
    host: config.host,
    port: config.port,
    connected: false
  }

  if config.auto_connect do
    send(self(), :auto_connect)
  end

  {:ok, state}
end

defp resolve_connection_config(opts) do
  %{
    host: resolve_host(opts),
    port: resolve_port(opts),
    auto_connect: resolve_auto_connect(opts)
  }
end

defp resolve_host(opts) do
  Keyword.get_lazy(opts, :host, fn ->
    System.get_env("MUD_HOST") || 
    Config.get(:connection, :host) || 
    "localhost"
  end)
  |> to_charlist()
end

defp resolve_port(opts) do
  Keyword.get_lazy(opts, :port, fn ->
    parse_env_port("MUD_PORT") || 
    Config.get(:connection, :port) || 
    @default_port
  end)
end

defp resolve_auto_connect(opts) do
  Keyword.get_lazy(opts, :auto_connect, fn ->
    Config.get(:connection, :auto_connect) || false
  end)
end
```

**Benefits:**
- Clearer separation of concerns
- Easier to test configuration resolution
- More maintainable init function

---

## Summary Statistics

- **High Priority Items:** 2 (code duplication, long functions)
- **Medium Priority Items:** 4 (error handling, scroll logic, config merging, god function)
- **Low Priority Items:** 5 (magic numbers, constants, naming, structs, init)

## Recommended Approach

Address these refactorings in the following order for maximum impact:

1. **UI event handling split (#2)** - Biggest maintainability win, makes the UI code much easier to work with
2. **Extract scroll logic (#5)** - Removes duplication and makes behavior more consistent
3. **Standardize error handling (#3)** - Improves API consistency across the codebase
4. **Break up render_debug_logs (#7)** - Improves readability of complex rendering code
5. **Host/port conversion extraction (#1)** - Small but useful utility
6. **Address lower priority items as time permits**

## Guidelines for Implementation

- Make changes incrementally, one refactoring at a time
- Write tests before refactoring (or ensure existing tests pass)
- Keep commits focused on a single refactoring
- Document any behavior changes in commit messages
- Consider backwards compatibility for public APIs
- Run the full test suite after each change

## Benefits of These Refactorings

- **Maintainability:** Smaller, focused functions are easier to understand and modify
- **Testability:** Extracted logic can be tested in isolation
- **Consistency:** Standardized patterns make the codebase more predictable
- **Readability:** Clear structure and naming improves code comprehension
- **Extensibility:** Well-factored code is easier to extend with new features
