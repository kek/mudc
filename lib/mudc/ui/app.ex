defmodule Mudc.UI.App do
  @moduledoc """
  Main terminal UI for the MUD client using term_ui's Elm Architecture.

  Features:
  - Scrollable viewport for game text with ANSI color support
  - Text input for commands
  - Command history (up/down arrows)
  - Status bar showing connection status

  Controls:
  - Enter: Send command
  - Up/Down: Navigate command history (when input is focused)
  - Page Up/Down: Scroll game text
  - Ctrl+C: Quit
  """

  use TermUI.Elm

  require Logger

  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection
  alias Mudc.UI.AnsiParser

  @max_lines 1000
  @viewport_height 20
  @log_viewport_height 15

  # ----------------------------------------------------------------------------
  # Component Callbacks
  # ----------------------------------------------------------------------------

  def init(_opts) do
    # Subscribe to events from other components
    Bus.subscribe(:game_text)
    Bus.subscribe(:connection)
    Bus.subscribe(:state_changed)

    # Subscribe to log updates
    Mudc.UI.LogBuffer.subscribe()

    %{
      # Game text lines (newest at the end)
      lines: ["Welcome to Mudc - MUME Client", "Type commands and press Enter to send"],
      scroll_offset: 0,
      auto_scroll: true,

      # Command input (simple string buffer)
      input_buffer: "",

      # Command history
      history: [],
      history_index: nil,

      # Connection status
      connected: false,
      status_message: "Not connected - press 'c' to connect",

      # GMCP data
      vitals: %{},
      room: %{},

      # Log viewer state
      show_logs: false,
      log_lines: [],
      log_scroll_offset: 0
    }
  end

  def event_to_msg(%Event.Key{key: :enter}, state) do
    {:msg, {:send_command, state.input_buffer}}
  end

  def event_to_msg(%Event.Key{key: :up, modifiers: mods}, %{history: history})
      when history != [] and mods == [] do
    {:msg, :history_prev}
  end

  def event_to_msg(%Event.Key{key: :down, modifiers: mods}, %{history_index: idx})
      when not is_nil(idx) and mods == [] do
    {:msg, :history_next}
  end

  def event_to_msg(%Event.Key{key: :page_up}, _state) do
    {:msg, {:scroll, -@viewport_height}}
  end

  def event_to_msg(%Event.Key{key: :page_down}, _state) do
    {:msg, {:scroll, @viewport_height}}
  end

  def event_to_msg(%Event.Key{key: :backspace}, _state) do
    {:msg, :backspace}
  end

  def event_to_msg(%Event.Key{key: "c"} = event, _state) do
    if Event.has_modifier?(event, :ctrl) do
      {:msg, :quit}
    else
      {:msg, {:char, "c"}}
    end
  end

  def event_to_msg(%Event.Key{key: "q"} = event, _state) do
    if Event.has_modifier?(event, :ctrl) do
      {:msg, :quit}
    else
      {:msg, {:char, "q"}}
    end
  end

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:msg, {:char, char}}
  end

  # F8 toggles log viewer
  def event_to_msg(%Event.Key{key: :f8}, _state) do
    {:msg, :toggle_logs}
  end

  # When log viewer is open, Page Up/Down scrolls logs
  def event_to_msg(%Event.Key{key: :page_up}, %{show_logs: true}) do
    {:msg, {:scroll_logs, -10}}
  end

  def event_to_msg(%Event.Key{key: :page_down}, %{show_logs: true}) do
    {:msg, {:scroll_logs, 10}}
  end

  def event_to_msg(_event, _state) do
    :ignore
  end

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
            history = [command | state.history] |> Enum.take(100)
            {%{state | input_buffer: "", history: history, history_index: nil}, []}

          {:error, :not_connected} ->
            new_state = add_local_line(state, "[Not connected - type /connect]")
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
    max_scroll = max(0, length(state.lines) - @viewport_height)
    new_offset = state.scroll_offset + delta
    new_offset = max(0, min(max_scroll, new_offset))
    auto_scroll = new_offset >= max_scroll
    {%{state | scroll_offset: new_offset, auto_scroll: auto_scroll}, []}
  end

  def update(:scroll_top, state) do
    {%{state | scroll_offset: 0, auto_scroll: false}, []}
  end

  def update(:scroll_bottom, state) do
    max_scroll = max(0, length(state.lines) - @viewport_height)
    {%{state | scroll_offset: max_scroll, auto_scroll: true}, []}
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update(:toggle_logs, state) do
    new_show = not state.show_logs

    # Load current logs when showing
    log_lines =
      if new_show do
        Mudc.UI.LogBuffer.get_logs()
      else
        state.log_lines
      end

    {%{state | show_logs: new_show, log_lines: log_lines, log_scroll_offset: 0}, []}
  end

  def update({:scroll_logs, delta}, state) do
    max_scroll = max(0, length(state.log_lines) - @log_viewport_height)
    new_offset = state.log_scroll_offset + delta
    new_offset = max(0, min(max_scroll, new_offset))
    {%{state | log_scroll_offset: new_offset}, []}
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
      |> Map.put(:status_message, "Connected to #{host}:#{port}")
      |> add_local_line("[Connected to #{host}:#{port}]")

    {state, []}
  end

  def handle_info({:event, :connection, :disconnected}, state) do
    state =
      state
      |> Map.put(:connected, false)
      |> Map.put(:status_message, "Disconnected")
      |> add_local_line("[Disconnected]")

    {state, []}
  end

  def handle_info({:event, :connection, {:error, reason}}, state) do
    state =
      state
      |> Map.put(:status_message, "Error: #{inspect(reason)}")
      |> add_local_line("[Connection error: #{inspect(reason)}]")

    {state, []}
  end

  def handle_info({:event, :state_changed, {:vitals, vitals}}, state) do
    {%{state | vitals: vitals}, []}
  end

  def handle_info({:event, :state_changed, {:room, room}}, state) do
    {%{state | room: room}, []}
  end

  # Handle log buffer updates
  def handle_info({:log_update, lines}, state) do
    # Only update if log viewer is visible
    if state.show_logs do
      {%{state | log_lines: Enum.reverse(lines)}, []}
    else
      {state, []}
    end
  end

  def handle_info(_msg, state) do
    {state, []}
  end

  def view(state) do
    main_view =
      stack(:vertical, [
        render_header(state),
        render_vitals_bar(state),
        render_viewport(state),
        text(""),
        render_input(state),
        render_status_bar(state)
      ])

    if state.show_logs do
      stack(:vertical, [
        main_view,
        text(""),
        render_log_window(state)
      ])
    else
      main_view
    end
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
        max(0, length(lines) - @viewport_height)
      else
        state.scroll_offset
      end

    %{state | lines: lines, scroll_offset: scroll_offset}
  end

  defp add_local_line(state, line) do
    add_game_line(state, line)
  end

  defp render_header(state) do
    title = "Mudc - MUME Client"

    connection_indicator =
      if state.connected do
        text(" [CONNECTED]", Style.new(fg: :green, attrs: [:bold]))
      else
        text(" [DISCONNECTED]", Style.new(fg: :red, attrs: [:bold]))
      end

    stack(:horizontal, [
      text(title, Style.new(fg: :cyan, attrs: [:bold])),
      connection_indicator
    ])
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
    visible_lines =
      state.lines
      |> Enum.drop(state.scroll_offset)
      |> Enum.take(@viewport_height)

    # Pad with empty lines if needed
    visible_lines =
      visible_lines ++ List.duplicate("", @viewport_height - length(visible_lines))

    line_elements =
      Enum.map(visible_lines, fn line ->
        # Parse ANSI escape sequences and render as styled text
        render_ansi_line(line)
      end)

    # Build viewport with border
    total_lines = length(state.lines)

    scroll_info =
      "#{state.scroll_offset + 1}-#{min(state.scroll_offset + @viewport_height, total_lines)}/#{total_lines}"

    top_border = "+" <> String.duplicate("-", 68) <> " " <> scroll_info <> " +"
    bottom_border = "+" <> String.duplicate("-", 78) <> "+"

    content =
      Enum.map(line_elements, fn elem ->
        stack(:horizontal, [
          text("| "),
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
    history_info =
      case state.history_index do
        nil -> ""
        idx -> " | History: #{idx + 1}/#{length(state.history)}"
      end

    status = state.status_message <> history_info
    text(status, Style.new(fg: :yellow, attrs: [:dim]))
  end

  defp render_log_window(state) do
    header_style = Style.new(fg: :magenta, attrs: [:bold])
    border_style = Style.new(fg: :magenta)

    visible_lines =
      state.log_lines
      |> Enum.drop(state.log_scroll_offset)
      |> Enum.take(@log_viewport_height)

    # Pad with empty lines if needed
    visible_lines =
      visible_lines ++ List.duplicate("", @log_viewport_height - length(visible_lines))

    total_logs = length(state.log_lines)

    scroll_info =
      if total_logs > 0 do
        first = state.log_scroll_offset + 1
        last = min(state.log_scroll_offset + @log_viewport_height, total_logs)
        " #{first}-#{last}/#{total_logs}"
      else
        " 0/0"
      end

    top_border = "+--- LOGS (F8 to close, PgUp/PgDn to scroll)" <> String.duplicate("-", 30) <> scroll_info <> " +"
    bottom_border = "+" <> String.duplicate("-", 78) <> "+"

    line_elements =
      Enum.map(visible_lines, fn line ->
        # Truncate long lines
        truncated = String.slice(line, 0, 76)
        text(truncated, Style.new(fg: :white, attrs: [:dim]))
      end)

    content =
      Enum.map(line_elements, fn elem ->
        stack(:horizontal, [
          text("| ", border_style),
          elem
        ])
      end)

    stack(:vertical, [
      text(top_border, header_style),
      stack(:vertical, content),
      text(bottom_border, border_style)
    ])
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Run the MUD client UI.

  Logs are captured by our custom LogHandler and can be viewed
  by pressing F8 to toggle the log window.
  """
  def run do
    TermUI.Runtime.run(root: __MODULE__)
  end
end
