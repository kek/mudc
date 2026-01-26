defmodule Mudc.UI.App do
  @moduledoc """
  Main terminal UI for the MUD client using term_ui's Elm Architecture.

  Features:
  - Scrollable viewport for game text with ANSI color support
  - Text input for commands
  - Command history (up/down arrows)
  - Status bar showing connection status
  - Debug log viewer (F4 - Dog screen)

  Controls:
  - Enter: Send command
  - Up/Down: Navigate command history
  - Ctrl+Arrow: Send directional commands (north/south/west/east)
  - Numpad: Send directional commands (8=n, 2=s, 4=w, 6=e, 7=nw, 9=ne, 1=sw, 3=se, 5=look)
  - Page Up/Down: Scroll game text
  - F3: Game screen (main view)
  - F4: Dog screen (debug logs)
  - F5: Cat screen
  - Ctrl+F5: Recompile code
  - Ctrl+C: Quit
  """

  use TermUI.Elm

  require Logger

  alias TermUI.Renderer.Style
  alias TermUI.Terminal
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection
  alias Mudc.UI.AnsiParser
  alias Mudc.UI.EventHandler
  alias Mudc.UI.ScrollUtils

  # Buffer configuration
  @max_lines 1000
  @max_history_size 100

  # Reserved lines: header(1) + tabs(1) + vitals(1) + top_border(1) + bottom_border(1) + empty(1) + input(1) + status(1) = 8
  @reserved_lines 8

  # Minimum viewport height to ensure readable display even on small terminals
  @min_viewport_height 5

  # Dog art padding: borders(2) + header space(1) + bottom padding(1) = 4
  # This ensures proper spacing around the ASCII art
  @dog_art_padding 4

  @dog_art """
      / \\__
     (    @\\___
     /         O
    /   (_____/
   /_____/   U
  """

  @cat_art """
   /\\_/\\
  ( o.o )
   > ^ <
  """

  # ----------------------------------------------------------------------------
  # Component Callbacks
  # ----------------------------------------------------------------------------

  def init(_opts) do
    # Subscribe to events from other components
    Bus.subscribe(:game_text)
    Bus.subscribe(:connection)
    Bus.subscribe(:state_changed)

    # Subscribe to log updates for dog screen
    Mudc.UI.LogBuffer.subscribe()

    # Get initial terminal dimensions
    {width, height} = get_terminal_size()
    viewport_height = calculate_viewport_height(height)

    %{
      # Terminal dimensions
      term_width: width,
      term_height: height,
      viewport_height: viewport_height,

      # Screen selection
      current_screen: :game,

      # Game text lines (newest at the end)
      lines: [
        "Welcome to Mudc - MUME Client",
        "Type /connect to connect, /disconnect to disconnect, /quit to exit",
        "Press F4 for debug logs | Ctrl+F5 to recompile | F3/F4/F5 switch screens"
      ],
      scroll_offset: 0,
      auto_scroll: true,

      # Command input (simple string buffer)
      input_buffer: "",

      # Command history
      history: [],
      history_index: nil,

      # Connection status
      connected: false,
      status_message:
        "Commands: /connect, /disconnect, /quit | Ctrl+Arrows: move | F4: debug logs | Ctrl+F5: recompile",

      # GMCP data
      vitals: %{},
      room: %{},

      # Debug logs for dog screen
      log_lines: [],
      dog_scroll_offset: 0,
      dog_auto_scroll: true
    }
  end

  # Delegate event handling to EventHandler module
  defdelegate event_to_msg(event, state), to: EventHandler

  def update({:send_command, ""}, state) do
    {state, []}
  end

  def update({:send_command, command}, state) do
    # Check for local commands
    case command do
      "/connect" ->
        Connection.connect()
        {%{state | input_buffer: ""}, []}

      "/disconnect" ->
        Connection.disconnect()
        {%{state | input_buffer: ""}, []}

      "/quit" ->
        {state, [:quit]}

      _ ->
        case Connection.send_command(command) do
          :ok ->
            history = [command | state.history] |> Enum.take(@max_history_size)
            {%{state | input_buffer: "", history: history, history_index: nil}, []}

          {:error, :not_connected} ->
            new_state = add_local_line(state, "[Not connected - use /connect to connect]")
            {%{new_state | input_buffer: ""}, []}

          {:error, reason} ->
            new_state = add_local_line(state, "[Send error: #{inspect(reason)}]")
            {new_state, []}
        end
    end
  end

  def update({:char, char}, state) do
    {%{state | input_buffer: state.input_buffer <> char}, []}
  end

  def update(:backspace, state) do
    new_buffer =
      if String.length(state.input_buffer) > 0 do
        String.slice(state.input_buffer, 0..-2//1)
      else
        ""
      end

    {%{state | input_buffer: new_buffer}, []}
  end

  def update(:history_prev, state) do
    new_index =
      case state.history_index do
        nil -> 0
        idx -> min(idx + 1, length(state.history) - 1)
      end

    command = Enum.at(state.history, new_index, "")
    {%{state | input_buffer: command, history_index: new_index}, []}
  end

  def update(:history_next, state) do
    case state.history_index do
      nil ->
        {state, []}

      0 ->
        {%{state | input_buffer: "", history_index: nil}, []}

      idx ->
        new_index = idx - 1
        command = Enum.at(state.history, new_index, "")
        {%{state | input_buffer: command, history_index: new_index}, []}
    end
  end

  def update({:scroll, delta}, state) do
    case state.current_screen do
      :game ->
        {new_offset, auto_scroll} =
          ScrollUtils.apply_scroll(
            state.scroll_offset,
            delta,
            length(state.lines),
            state.viewport_height
          )

        {%{state | scroll_offset: new_offset, auto_scroll: auto_scroll}, []}

      :dog ->
        # Calculate viewport height for dog logs
        dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
        dog_height = dog_lines_count + @dog_art_padding
        log_viewport_height = max(state.term_height - @reserved_lines - dog_height, @min_viewport_height)

        {new_offset, dog_auto_scroll} =
          ScrollUtils.apply_scroll(
            state.dog_scroll_offset,
            delta,
            length(state.log_lines),
            log_viewport_height
          )

        {%{state | dog_scroll_offset: new_offset, dog_auto_scroll: dog_auto_scroll}, []}

      _ ->
        {state, []}
    end
  end

  def update(:scroll_top, state) do
    {offset, auto_scroll} = ScrollUtils.scroll_to_top()

    case state.current_screen do
      :game ->
        {%{state | scroll_offset: offset, auto_scroll: auto_scroll}, []}

      :dog ->
        {%{state | dog_scroll_offset: offset, dog_auto_scroll: auto_scroll}, []}

      _ ->
        {state, []}
    end
  end

  def update(:scroll_bottom, state) do
    case state.current_screen do
      :game ->
        {offset, auto_scroll} =
          ScrollUtils.scroll_to_bottom(length(state.lines), state.viewport_height)

        {%{state | scroll_offset: offset, auto_scroll: auto_scroll}, []}

      :dog ->
        dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
        dog_height = dog_lines_count + @dog_art_padding
        log_viewport_height = max(state.term_height - @reserved_lines - dog_height, @min_viewport_height)

        {offset, auto_scroll} =
          ScrollUtils.scroll_to_bottom(length(state.log_lines), log_viewport_height)

        {%{state | dog_scroll_offset: offset, dog_auto_scroll: auto_scroll}, []}

      _ ->
        {state, []}
    end
  end

  def update({:resize, width, height}, state) do
    viewport_height = calculate_viewport_height(height)

    # Adjust scroll offsets if needed
    scroll_offset = ScrollUtils.clamp_scroll(state.scroll_offset, length(state.lines), viewport_height)

    # Also adjust dog screen scroll offset
    dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
    dog_height = dog_lines_count + @dog_art_padding
    log_viewport_height = max(height - @reserved_lines - dog_height, @min_viewport_height)
    dog_scroll_offset =
      ScrollUtils.clamp_scroll(state.dog_scroll_offset, length(state.log_lines), log_viewport_height)

    {%{
       state
       | term_width: width,
         term_height: height,
         viewport_height: viewport_height,
         scroll_offset: scroll_offset,
         dog_scroll_offset: dog_scroll_offset
     }, []}
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update(:recompile, state) do
    state = add_local_line(state, "[Recompiling...]")

    try do
      case IEx.Helpers.recompile() do
        {:ok, _} ->
          add_local_line(state, "[Recompile successful]")

        {:error, _} ->
          add_local_line(state, "[Recompile failed]")

        :noop ->
          add_local_line(state, "[No changes to recompile]")
      end
    rescue
      e ->
        add_local_line(state, "[Recompile error: #{inspect(e)}]")
    end
  end

  def update({:switch_screen, screen}, state) do
    {%{state | current_screen: screen}, []}
  end

  def update(_msg, state) do
    {state, []}
  end

  # Handle info messages from event bus
  def handle_info({:event, :game_text, {:text, data}}, state) do
    # Split data into lines and add to buffer
    new_lines =
      data
      |> String.split(~r/\r?\n/)
      |> Enum.reject(&(&1 == ""))

    state = Enum.reduce(new_lines, state, &add_game_line(&2, &1))
    {state, []}
  end

  def handle_info({:event, :game_text, :prompt}, state) do
    # Prompt received (GA) - could be used for prompt detection
    {state, []}
  end

  def handle_info({:event, :connection, {:connected, host, port}}, state) do
    state =
      state
      |> Map.put(:connected, true)
      |> Map.put(:status_message, "Connected to #{host}:#{port} | Commands: /disconnect, /quit")
      |> add_local_line("[Connected to #{host}:#{port}]")

    {state, []}
  end

  def handle_info({:event, :connection, :disconnected}, state) do
    state =
      state
      |> Map.put(:connected, false)
      |> Map.put(:status_message, "Disconnected | Use /connect to reconnect")
      |> add_local_line("[Disconnected]")

    {state, []}
  end

  def handle_info({:event, :connection, {:error, reason}}, state) do
    error_msg = format_connection_error(reason)

    state =
      state
      |> Map.put(:status_message, "Connection failed: #{error_msg}")
      |> add_local_line("[Connection error: #{inspect(reason)}]")
      |> add_local_line("[#{error_msg}]")

    {state, []}
  end

  def handle_info({:event, :state_changed, {:vitals, vitals}}, state) do
    {%{state | vitals: vitals}, []}
  end

  def handle_info({:event, :state_changed, {:room, room}}, state) do
    {%{state | room: room}, []}
  end

  # Handle log buffer updates for dog screen
  def handle_info({:log_update, lines}, state) do
    log_lines = Enum.reverse(lines)

    # Auto-scroll if enabled
    dog_scroll_offset =
      if state.dog_auto_scroll do
        # Calculate viewport height for dog logs
        dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
        dog_height = dog_lines_count + @dog_art_padding
        log_viewport_height = max(state.term_height - @reserved_lines - dog_height, @min_viewport_height)

        ScrollUtils.calculate_max_scroll(length(log_lines), log_viewport_height)
      else
        state.dog_scroll_offset
      end

    {%{state | log_lines: log_lines, dog_scroll_offset: dog_scroll_offset}, []}
  end

  def handle_info(_msg, state) do
    {state, []}
  end

  def view(state) do
    case state.current_screen do
      :game -> render_game_screen(state)
      :dog -> render_dog_screen(state)
      :cat -> render_cat_screen(state)
    end
  end

  # ----------------------------------------------------------------------------
  # Screen Renderers
  # ----------------------------------------------------------------------------

  defp render_game_screen(state) do
    stack(:vertical, [
      render_header(state),
      render_screen_tabs(state),
      render_vitals_bar(state),
      render_viewport(state),
      text(""),
      render_input(state),
      render_status_bar(state)
    ])
  end

  defp render_dog_screen(state) do
    stack(:vertical, [
      render_header(state),
      render_screen_tabs(state),
      render_debug_logs(state),
      text(""),
      render_input(state),
      render_status_bar(state)
    ])
  end

  defp render_cat_screen(state) do
    stack(:vertical, [
      render_header(state),
      render_screen_tabs(state),
      render_ascii_art(:cat),
      text(""),
      render_input(state),
      render_status_bar(state)
    ])
  end

  defp render_screen_tabs(state) do
    tabs = [
      {"F3: Game", state.current_screen == :game},
      {"F4: Dog", state.current_screen == :dog},
      {"F5: Cat", state.current_screen == :cat}
    ]

    tab_elements =
      Enum.map(tabs, fn {label, active} ->
        style =
          if active do
            Style.new(fg: :cyan, attrs: [:bold, :reverse])
          else
            Style.new(fg: :white, attrs: [:dim])
          end

        text("  #{label}  ", style)
      end)

    stack(:horizontal, [
      text("[", Style.new(fg: :blue)),
      stack(:horizontal, tab_elements),
      text("]", Style.new(fg: :blue))
    ])
  end

  defp render_ascii_art(type) do
    art_text =
      case type do
        :dog -> @dog_art
        :cat -> @cat_art
      end

    art_lines = String.split(art_text, "\n", trim: true)

    line_elements =
      Enum.map(art_lines, fn line ->
        text(line, Style.new(fg: :bright_yellow, attrs: [:bold]))
      end)

    stack(:vertical, [
      text("+" <> String.duplicate("-", 40) <> "+", Style.new(fg: :blue)),
      text(""),
      stack(:vertical, line_elements),
      text(""),
      text("+" <> String.duplicate("-", 40) <> "+", Style.new(fg: :blue))
    ])
  end

  defp render_debug_logs(state) do
    {dog_lines, log_viewport_height} = calculate_log_viewport_dimensions(state)
    visible_logs = get_visible_log_lines(state, log_viewport_height)
    scroll_info = build_scroll_info(state, log_viewport_height)

    dog_elements = render_dog_art(dog_lines)
    log_elements = render_log_lines(visible_logs)
    log_header = build_log_header(state, scroll_info)

    border_width = min(state.term_width - 2, 78)
    border = text("+" <> String.duplicate("-", border_width) <> "+", Style.new(fg: :blue))

    stack(:vertical, [
      border,
      stack(:vertical, dog_elements),
      border,
      text(log_header, Style.new(fg: :cyan, attrs: [:bold])),
      border,
      stack(:vertical, log_elements),
      border
    ])
  end

  defp calculate_log_viewport_dimensions(state) do
    # Calculate how many lines we can show for logs
    # Reserved: header(1) + tabs(1) + vitals(1) + borders(2) + empty(1) + input(1) + status(1) = 8
    available_height = state.term_height - @reserved_lines

    # Show dog art at top (takes ~7 lines)
    dog_lines = String.split(@dog_art, "\n", trim: true)
    dog_height = length(dog_lines) + @dog_art_padding

    # Remaining space for logs
    log_viewport_height = max(available_height - dog_height, @min_viewport_height)

    {dog_lines, log_viewport_height}
  end

  defp get_visible_log_lines(state, log_viewport_height) do
    # Get logs based on scroll offset
    visible_logs =
      state.log_lines
      |> Enum.drop(state.dog_scroll_offset)
      |> Enum.take(log_viewport_height)

    # Pad with empty lines if needed
    visible_logs ++ List.duplicate("", log_viewport_height - length(visible_logs))
  end

  defp build_scroll_info(state, log_viewport_height) do
    total_logs = length(state.log_lines)

    if total_logs > 0 do
      first = state.dog_scroll_offset + 1
      last = min(state.dog_scroll_offset + log_viewport_height, total_logs)
      "#{first}-#{last}/#{total_logs}"
    else
      "0/0"
    end
  end

  defp render_dog_art(dog_lines) do
    Enum.map(dog_lines, fn line ->
      text("  " <> line, Style.new(fg: :bright_yellow, attrs: [:bold]))
    end)
  end

  defp render_log_lines(visible_logs) do
    Enum.map(visible_logs, fn line ->
      style = log_line_style(line)
      text(line, style)
    end)
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

  defp build_log_header(state, scroll_info) do
    border_width = min(state.term_width - 2, 78)
    scroll_info_len = String.length(scroll_info)
    label = "DEBUG LOGS "
    padding_size = max(border_width - scroll_info_len - String.length(label) - 3, 0)

    label <> String.duplicate(" ", padding_size) <> " " <> scroll_info
  end

  # ----------------------------------------------------------------------------
  # Private Helpers
  # ----------------------------------------------------------------------------

  defp add_game_line(state, line) do
    lines = state.lines ++ [line]
    lines = Enum.take(lines, -@max_lines)

    # Auto-scroll if enabled
    scroll_offset =
      if state.auto_scroll do
        ScrollUtils.calculate_max_scroll(length(lines), state.viewport_height)
      else
        state.scroll_offset
      end

    %{state | lines: lines, scroll_offset: scroll_offset}
  end

  defp add_local_line(state, line) do
    add_game_line(state, line)
  end

  defp format_connection_error(:econnrefused) do
    "Make sure MMapper is running on localhost:4242, or use /connect to try again"
  end

  defp format_connection_error(:nxdomain) do
    "Host not found. Check your connection settings in ~/.config/mudc/config.toml"
  end

  defp format_connection_error(:timeout) do
    "Connection timeout. Check if the server is reachable"
  end

  defp format_connection_error(_reason) do
    "Connection failed. Use /connect to try again"
  end

  defp render_header(_state) do
    title = "Mudc - MUME Client"
    text(title, Style.new(fg: :cyan, attrs: [:bold]))
  end

  defp render_vitals_bar(state) do
    vitals = state.vitals

    if map_size(vitals) > 0 do
      # MUME-specific vitals display
      hp = Map.get(vitals, "hp", Map.get(vitals, "hits", "?"))
      max_hp = Map.get(vitals, "maxhp", Map.get(vitals, "maxhits", "?"))
      mana = Map.get(vitals, "mana", "?")
      max_mana = Map.get(vitals, "maxmana", "?")
      moves = Map.get(vitals, "moves", Map.get(vitals, "mv", "?"))
      max_moves = Map.get(vitals, "maxmoves", Map.get(vitals, "maxmv", "?"))

      hp_style = vitals_color(hp, max_hp)
      mana_style = vitals_color(mana, max_mana)
      moves_style = vitals_color(moves, max_moves)

      stack(:horizontal, [
        text("HP:", Style.new(fg: :white)),
        text("#{hp}/#{max_hp}", hp_style),
        text("  Mana:", Style.new(fg: :white)),
        text("#{mana}/#{max_mana}", mana_style),
        text("  Moves:", Style.new(fg: :white)),
        text("#{moves}/#{max_moves}", moves_style)
      ])
    else
      text("")
    end
  end

  defp vitals_color(current, max) when is_integer(current) and is_integer(max) and max > 0 do
    ratio = current / max

    cond do
      ratio > 0.7 -> Style.new(fg: :green)
      ratio > 0.3 -> Style.new(fg: :yellow)
      true -> Style.new(fg: :red, attrs: [:bold])
    end
  end

  defp vitals_color(_current, _max) do
    Style.new(fg: :white)
  end

  # Render a single line with ANSI color support
  defp render_ansi_line(""), do: text("")

  defp render_ansi_line(line) do
    segments = AnsiParser.parse(line)

    case segments do
      [] ->
        text("")

      [{text_content, nil}] ->
        # Single unstyled segment - simple case
        text(text_content)

      [{text_content, style}] ->
        # Single styled segment
        text(text_content, style)

      _ ->
        # Multiple segments - render as horizontal stack
        nodes = AnsiParser.to_render_nodes(segments)
        stack(:horizontal, nodes)
    end
  end

  defp render_viewport(state) do
    viewport_height = state.viewport_height

    visible_lines =
      state.lines
      |> Enum.drop(state.scroll_offset)
      |> Enum.take(viewport_height)

    # Pad with empty lines if needed
    visible_lines =
      visible_lines ++ List.duplicate("", viewport_height - length(visible_lines))

    line_elements =
      Enum.map(visible_lines, fn line ->
        # Parse ANSI escape sequences and render as styled text
        render_ansi_line(line)
      end)

    # Build viewport with border
    total_lines = length(state.lines)

    scroll_info =
      "#{state.scroll_offset + 1}-#{min(state.scroll_offset + viewport_height, total_lines)}/#{total_lines}"

    # Use terminal width for borders, minus 2 for the "| " prefix
    border_width = max(state.term_width - 2, 20)
    scroll_info_len = String.length(scroll_info)

    top_border =
      "+" <>
        String.duplicate("-", border_width - scroll_info_len - 3) <> " " <> scroll_info <> " +"

    bottom_border = "+" <> String.duplicate("-", border_width) <> "+"

    content =
      Enum.map(line_elements, fn elem ->
        stack(:horizontal, [
          elem
        ])
      end)

    stack(:vertical, [
      text(top_border, Style.new(fg: :blue)),
      stack(:vertical, content),
      text(bottom_border, Style.new(fg: :blue))
    ])
  end

  defp render_input(state) do
    border_style = Style.new(fg: :green)
    # Show cursor as underscore at end of input
    cursor = "_"
    display_text = state.input_buffer <> cursor

    stack(:vertical, [
      stack(:horizontal, [
        text("> ", border_style),
        text(display_text)
      ])
    ])
  end

  defp render_status_bar(state) do
    base_status =
      case state.current_screen do
        :game ->
          state.status_message

        :dog ->
          scroll_status =
            if state.dog_auto_scroll, do: "Live", else: "Paused (scroll down to resume)"

          "Debug Logs - #{scroll_status} | F3: return to game"

        :cat ->
          "Viewing Cat Screen (F3: return to game)"
      end

    history_info =
      case state.history_index do
        nil -> ""
        idx -> " | History: #{idx + 1}/#{length(state.history)}"
      end

    recompile_hint = " | Ctrl+F5: recompile"

    status = base_status <> history_info <> recompile_hint
    text(status, Style.new(fg: :yellow, attrs: [:dim]))
  end

  # ----------------------------------------------------------------------------
  # Terminal Size Helpers
  # ----------------------------------------------------------------------------

  defp get_terminal_size do
    case Terminal.get_terminal_size() do
      {:ok, {rows, cols}} -> {cols, rows}
      {:error, _} -> {80, 24}
    end
  end

  defp calculate_viewport_height(term_height) do
    # Calculate viewport height based on terminal height minus reserved lines
    max(term_height - @reserved_lines, @min_viewport_height)
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Run the MUD client UI.
  """
  def run do
    TermUI.Runtime.run(root: __MODULE__)
  end
end
