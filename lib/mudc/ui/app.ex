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
  - Ctrl+Arrow: Send directional commands (north/south/west/east)
  - Page Up/Down: Scroll game text
  - F9: Toggle between game window and IEx REPL
  - Ctrl+C: Quit
  """

  use TermUI.Elm

  require Logger

  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Terminal
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection
  alias Mudc.UI.AnsiParser

  @max_lines 1000
  # Reserved lines: header(1) + vitals(1) + top_border(1) + bottom_border(1) + empty(1) + input(1) + status(1) = 7
  @reserved_lines 7

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

    # Get initial terminal dimensions
    {width, height} = get_terminal_size()
    viewport_height = calculate_viewport_height(height)

    %{
      # Terminal dimensions
      term_width: width,
      term_height: height,
      viewport_height: viewport_height,
      log_viewport_height: div(viewport_height, 2),

      # Game text lines (newest at the end)
      lines: [
        "Welcome to Mudc - MUME Client",
        "Type /connect to connect, /disconnect to disconnect, /quit to exit",
        "Press F5 to recompile, F8 to view logs, F9 to toggle IEx REPL"
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
        "Commands: /connect, /disconnect, /quit | Ctrl+Arrows: move | F5: recompile | F8: logs | F9: IEx",

      # GMCP data
      vitals: %{},
      room: %{},

      # Log viewer state
      show_logs: false,
      log_lines: [],
      log_scroll_offset: 0,

      # IEx toggle state
      iex_mode: false
    }
  end

  def event_to_msg(%Event.Key{key: :enter}, state) do
    {:msg, {:send_command, state.input_buffer}}
  end

  # History navigation (up/down without modifiers)
  def event_to_msg(%Event.Key{key: :up, modifiers: []}, %{history: history})
      when history != [] do
    {:msg, :history_prev}
  end

  def event_to_msg(%Event.Key{key: :down, modifiers: []}, %{history_index: idx})
      when not is_nil(idx) do
    {:msg, :history_next}
  end

  # Ctrl+Arrow for directional movement
  def event_to_msg(%Event.Key{key: :up, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "north"}}
  end

  def event_to_msg(%Event.Key{key: :down, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "south"}}
  end

  def event_to_msg(%Event.Key{key: :left, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "west"}}
  end

  def event_to_msg(%Event.Key{key: :right, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "east"}}
  end

  def event_to_msg(%Event.Key{key: :backspace}, _state), do: {:msg, :backspace}

  # Ctrl+C and Ctrl+Q quit
  def event_to_msg(%Event.Key{key: key, modifiers: [:ctrl]}, _state) when key in ["c", "q"] do
    {:msg, :quit}
  end

  def event_to_msg(%Event.Key{key: key}, _state) when key in ["c", "q"] do
    {:msg, {:char, key}}
  end

  # Ctrl+L is ignored (terminal clear)
  def event_to_msg(%Event.Key{key: "l", modifiers: [:ctrl]}, _state), do: :ignore

  def event_to_msg(%Event.Key{key: "l"}, _state), do: {:msg, {:char, "l"}}

  # Function keys
  def event_to_msg(%Event.Key{key: :f5}, _state), do: {:msg, :recompile}
  def event_to_msg(%Event.Key{key: :f8}, _state), do: {:msg, :toggle_logs}
  def event_to_msg(%Event.Key{key: :f9}, _state), do: {:msg, :toggle_iex}

  # Page Up/Down - log scrolling when logs are open, game text otherwise
  def event_to_msg(%Event.Key{key: :page_up}, %{show_logs: true}), do: {:msg, {:scroll_logs, -10}}

  def event_to_msg(%Event.Key{key: :page_down}, %{show_logs: true}),
    do: {:msg, {:scroll_logs, 10}}

  def event_to_msg(%Event.Key{key: :page_up}, state),
    do: {:msg, {:scroll, -state.viewport_height}}

  def event_to_msg(%Event.Key{key: :page_down}, state),
    do: {:msg, {:scroll, state.viewport_height}}

  # Regular character input
  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:msg, {:char, char}}
  end

  # Terminal resize
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(_event, _state), do: :ignore

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
    max_scroll = max(0, length(state.lines) - state.viewport_height)
    new_offset = state.scroll_offset + delta
    new_offset = max(0, min(max_scroll, new_offset))
    auto_scroll = new_offset >= max_scroll
    {%{state | scroll_offset: new_offset, auto_scroll: auto_scroll}, []}
  end

  def update(:scroll_top, state) do
    {%{state | scroll_offset: 0, auto_scroll: false}, []}
  end

  def update(:scroll_bottom, state) do
    max_scroll = max(0, length(state.lines) - state.viewport_height)
    {%{state | scroll_offset: max_scroll, auto_scroll: true}, []}
  end

  def update({:resize, width, height}, state) do
    viewport_height = calculate_viewport_height(height)
    log_viewport_height = div(viewport_height, 2)

    # Adjust scroll offsets if needed
    max_scroll = max(0, length(state.lines) - viewport_height)
    scroll_offset = min(state.scroll_offset, max_scroll)

    # Calculate actual popup viewport height
    actual_log_viewport_height = calculate_log_popup_viewport_height(height)
    max_log_scroll = max(0, length(state.log_lines) - actual_log_viewport_height)
    log_scroll_offset = min(state.log_scroll_offset, max_log_scroll)

    {%{
       state
       | term_width: width,
         term_height: height,
         viewport_height: viewport_height,
         log_viewport_height: log_viewport_height,
         scroll_offset: scroll_offset,
         log_scroll_offset: log_scroll_offset
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
          add_local_line(state, "[Recompile failed - check logs with F8]")

        :noop ->
          add_local_line(state, "[No changes to recompile]")
      end
    rescue
      e ->
        add_local_line(state, "[Recompile error: #{inspect(e)}]")
    end
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

  def update(:toggle_iex, state) do
    new_mode = not state.iex_mode

    if new_mode do
      # Switching to IEx mode
      state =
        add_local_line(state, "[Switching to IEx REPL - Call Mudc.UI.App.resume_ui() to return]")

      # Spawn a task to handle the terminal switch
      spawn(fn ->
        # Small delay to let the message render
        Process.sleep(100)

        # Disable raw mode and restore terminal
        Terminal.disable_raw_mode()

        # Clear screen and show cursor
        IO.write([
          IO.ANSI.clear(),
          IO.ANSI.cursor(0, 0),
          "\e[?25h"
        ])

        IO.puts("\n" <> IO.ANSI.green() <> "=== IEx REPL Mode ===" <> IO.ANSI.reset())
        IO.puts("You can now use IEx normally.")

        IO.puts(
          "Call " <>
            IO.ANSI.cyan() <>
            "Mudc.UI.App.resume_ui()" <> IO.ANSI.reset() <> " to return to the game window."
        )

        IO.puts("")
      end)

      {%{state | iex_mode: new_mode}, []}
    else
      # Switching back to game mode
      Terminal.enable_raw_mode()

      # Force a re-render
      IO.write([
        IO.ANSI.clear(),
        IO.ANSI.cursor(0, 0)
      ])

      state = add_local_line(state, "[Returned to game window]")
      {%{state | iex_mode: new_mode}, []}
    end
  end

  def update({:scroll_logs, delta}, state) do
    # Calculate actual popup viewport height
    actual_log_viewport_height = calculate_log_popup_viewport_height(state.term_height)

    max_scroll = max(0, length(state.log_lines) - actual_log_viewport_height)
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
      # Render log popup as overlay - completely replace the view
      render_log_popup_overlay(state)
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
        max(0, length(lines) - state.viewport_height)
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

  defp render_log_popup_overlay(state) do
    header_style = Style.new(fg: :yellow, bg: :black, attrs: [:bold])
    border_style = Style.new(fg: :yellow, bg: :black, attrs: [:bold])
    content_style = Style.new(fg: :white, bg: :black)

    # Calculate popup dimensions - use 80% of terminal size, min 40 cols x 15 rows
    popup_width = max(div(state.term_width * 4, 5), 40)
    popup_height = max(div(state.term_height * 4, 5), 15)
    # Subtract borders and header (4 lines)
    log_viewport_height = calculate_log_popup_viewport_height(state.term_height)

    # Calculate centering margins
    left_margin = max(div(state.term_width - popup_width, 2), 0)
    top_margin = max(div(state.term_height - popup_height, 2), 0)

    visible_lines =
      state.log_lines
      |> Enum.drop(state.log_scroll_offset)
      |> Enum.take(log_viewport_height)

    # Pad with empty lines if needed
    visible_lines =
      visible_lines ++ List.duplicate("", log_viewport_height - length(visible_lines))

    total_logs = length(state.log_lines)

    scroll_info =
      if total_logs > 0 do
        first = state.log_scroll_offset + 1
        last = min(state.log_scroll_offset + log_viewport_height, total_logs)
        " #{first}-#{last}/#{total_logs} "
      else
        " 0/0 "
      end

    # Build centered popup
    inner_width = popup_width - 4
    header_text = " LOGS - Press F8 to close, PgUp/PgDn to scroll "
    header_padding = max(inner_width - String.length(header_text) - String.length(scroll_info), 0)

    top_border = "╔" <> String.duplicate("═", popup_width - 2) <> "╗"

    header_line =
      "║ " <> header_text <> String.duplicate(" ", header_padding) <> scroll_info <> "║"

    separator = "╠" <> String.duplicate("═", popup_width - 2) <> "╣"
    bottom_border = "╚" <> String.duplicate("═", popup_width - 2) <> "╝"

    # Create empty background lines to fill screen
    empty_line = String.duplicate(" ", state.term_width)
    background_style = Style.new(fg: :black, bg: :black, attrs: [:dim])

    # Top padding before popup
    top_padding = List.duplicate(text(empty_line, background_style), top_margin)

    # Bottom padding after popup
    bottom_padding_count = max(state.term_height - popup_height - top_margin, 0)
    bottom_padding = List.duplicate(text(empty_line, background_style), bottom_padding_count)

    # Render log content lines with margins
    margin = String.duplicate(" ", left_margin)
    right_margin_size = max(state.term_width - popup_width - left_margin, 0)
    right_margin = String.duplicate(" ", right_margin_size)

    content_lines =
      Enum.map(visible_lines, fn line ->
        # Truncate and pad line to fit popup width
        truncated = String.slice(line, 0, inner_width)
        padded = String.pad_trailing(truncated, inner_width)
        padded_line = "║ " <> padded <> " ║"
        text(margin <> padded_line <> right_margin, content_style)
      end)

    # Build full screen with popup centered
    stack(
      :vertical,
      top_padding ++
        [
          text(margin <> top_border <> right_margin, border_style),
          text(margin <> header_line <> right_margin, header_style),
          text(margin <> separator <> right_margin, border_style)
        ] ++
        content_lines ++
        [
          text(margin <> bottom_border <> right_margin, border_style)
        ] ++
        bottom_padding
    )
  end

  # ----------------------------------------------------------------------------
  # Terminal Size Helpers
  # ----------------------------------------------------------------------------

  defp calculate_log_popup_viewport_height(term_height) do
    # Calculate popup dimensions - use 80% of terminal size, min 15 rows
    popup_height = max(div(term_height * 4, 5), 15)
    # Subtract borders and header (4 lines: top border, header, separator, bottom border)
    max(popup_height - 4, 5)
  end

  defp get_terminal_size do
    case Terminal.get_terminal_size() do
      {:ok, {rows, cols}} -> {cols, rows}
      {:error, _} -> {80, 24}
    end
  end

  defp calculate_viewport_height(term_height) do
    # Calculate viewport height based on terminal height minus reserved lines
    max(term_height - @reserved_lines, 5)
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

  @doc """
  Resume the UI after switching to IEx mode with F9.

  This function re-enables raw mode and returns you to the game window.
  """
  def resume_ui do
    # Re-enable raw mode
    case Terminal.enable_raw_mode() do
      {:ok, _} ->
        # Clear screen and hide cursor
        IO.write([
          IO.ANSI.clear(),
          IO.ANSI.cursor(0, 0),
          "\e[?25l"
        ])

        # Send a message to the app to update its state
        case Process.whereis(TermUI.Runtime) do
          nil ->
            IO.puts("Error: UI runtime not found")
            :error

          pid ->
            # Send toggle message to switch back from IEx mode
            TermUI.Runtime.send_message(pid, :root, :toggle_iex)
            IO.puts(IO.ANSI.green() <> "Returning to game window..." <> IO.ANSI.reset())
            Process.sleep(100)
            :ok
        end

      {:error, reason} ->
        IO.puts("Error re-enabling raw mode: #{inspect(reason)}")
        :error
    end
  end
end
