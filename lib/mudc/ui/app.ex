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
  alias Mudc.UI.EventHandler
  alias Mudc.UI.Screens.GameScreen
  alias Mudc.UI.Screens.DebugScreen
  alias Mudc.UI.Screens.InfoScreen

  # Configuration
  @max_history_size 100

  # Reserved lines: header(1) + tabs(1) + vitals(1) + top_border(1) + bottom_border(1) + empty(1) + input(1) + status(1) = 8
  @reserved_lines 8

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

      # Screens
      game_screen: GameScreen.new(),
      debug_screen: DebugScreen.new(),
      info_screen: InfoScreen.new(),

      # Command input (simple string buffer)
      input_buffer: "",

      # Command history
      history: [],
      history_index: nil,

      # Connection status
      connected: false,
      status_message:
        "Type /help for commands | Ctrl+Arrows: move | F3/F4/F5: screens | Ctrl+C: quit"
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
      "/help" ->
        help_text = """
        Available commands:
          /help        - Show this help message
          /connect     - Connect to the MUD server
          /disconnect  - Disconnect from the server
          /quit        - Exit Mudc

        Navigation:
          Ctrl+Arrows  - Send directional commands (north/south/east/west)
          Numpad       - Movement (8=n, 2=s, 4=w, 6=e, 7=nw, 9=ne, 1=sw, 3=se, 5=look)
          Up/Down      - Navigate command history
          Page Up/Down - Scroll game text

        Screens:
          F3           - Game screen (main view)
          F4           - Debug log screen
          F5           - Info screen

        Other:
          Ctrl+F5      - Recompile code (development)
          Ctrl+C       - Quit
        """

        Bus.publish(:game_text, {:text, help_text})
        {%{state | input_buffer: ""}, []}

      "/connect" ->
        Connection.connect()
        {%{state | input_buffer: ""}, []}

      "/disconnect" ->
        Connection.disconnect()
        {%{state | input_buffer: ""}, []}

      "/quit" ->
        {state, [:quit]}

      _ ->
        # Publish user input event for logging
        Bus.publish(:user_input, command)

        case Connection.send_command(command) do
          :ok ->
            history = [command | state.history] |> Enum.take(@max_history_size)
            {%{state | input_buffer: "", history: history, history_index: nil}, []}

          {:error, :not_connected} ->
            game_screen =
              GameScreen.add_line(
                state.game_screen,
                "[Not connected - use /connect to connect]",
                state.viewport_height
              )

            {%{state | input_buffer: "", game_screen: game_screen}, []}

          {:error, reason} ->
            game_screen =
              GameScreen.add_line(
                state.game_screen,
                "[Send error: #{inspect(reason)}]",
                state.viewport_height
              )

            {%{state | input_buffer: "", game_screen: game_screen}, []}
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
    state =
      case state.current_screen do
        :game ->
          game_screen = GameScreen.handle_scroll(state.game_screen, delta, state.viewport_height)
          %{state | game_screen: game_screen}

        :dog ->
          debug_screen =
            DebugScreen.handle_scroll(
              state.debug_screen,
              delta,
              state.term_height,
              @reserved_lines
            )

          %{state | debug_screen: debug_screen}

        _ ->
          state
      end

    {state, []}
  end

  def update(:scroll_top, state) do
    state =
      case state.current_screen do
        :game ->
          game_screen = GameScreen.scroll_to_top(state.game_screen)
          %{state | game_screen: game_screen}

        :dog ->
          debug_screen = DebugScreen.scroll_to_top(state.debug_screen)
          %{state | debug_screen: debug_screen}

        _ ->
          state
      end

    {state, []}
  end

  def update(:scroll_bottom, state) do
    state =
      case state.current_screen do
        :game ->
          game_screen = GameScreen.scroll_to_bottom(state.game_screen, state.viewport_height)
          %{state | game_screen: game_screen}

        :dog ->
          debug_screen =
            DebugScreen.scroll_to_bottom(state.debug_screen, state.term_height, @reserved_lines)

          %{state | debug_screen: debug_screen}

        _ ->
          state
      end

    {state, []}
  end

  def update({:resize, width, height}, state) do
    viewport_height = calculate_viewport_height(height)

    # Update screen scroll offsets
    game_screen = GameScreen.handle_resize(state.game_screen, viewport_height)
    debug_screen = DebugScreen.handle_resize(state.debug_screen, height, @reserved_lines)

    {%{
       state
       | term_width: width,
         term_height: height,
         viewport_height: viewport_height,
         game_screen: game_screen,
         debug_screen: debug_screen
     }, []}
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update(:recompile, state) do
    game_screen =
      GameScreen.add_line(state.game_screen, "[Recompiling...]", state.viewport_height)

    state = %{state | game_screen: game_screen}

    game_screen =
      try do
        case IEx.Helpers.recompile() do
          {:ok, _} ->
            GameScreen.add_line(
              state.game_screen,
              "[Recompile successful]",
              state.viewport_height
            )

          {:error, _} ->
            GameScreen.add_line(state.game_screen, "[Recompile failed]", state.viewport_height)

          :noop ->
            GameScreen.add_line(
              state.game_screen,
              "[No changes to recompile]",
              state.viewport_height
            )
        end
      rescue
        e ->
          GameScreen.add_line(
            state.game_screen,
            "[Recompile error: #{inspect(e)}]",
            state.viewport_height
          )
      end

    {%{state | game_screen: game_screen}, []}
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

    game_screen =
      Enum.reduce(new_lines, state.game_screen, fn line, screen ->
        GameScreen.add_line(screen, line, state.viewport_height)
      end)

    {%{state | game_screen: game_screen}, []}
  end

  def handle_info({:event, :game_text, :prompt}, state) do
    # Prompt received (GA) - could be used for prompt detection
    {state, []}
  end

  def handle_info({:event, :connection, {:connected, host, port}}, state) do
    game_screen =
      GameScreen.add_line(
        state.game_screen,
        "[Connected to #{host}:#{port}]",
        state.viewport_height
      )

    state =
      state
      |> Map.put(:connected, true)
      |> Map.put(:status_message, "Connected to #{host}:#{port} | Commands: /disconnect, /quit")
      |> Map.put(:game_screen, game_screen)

    {state, []}
  end

  def handle_info({:event, :connection, :disconnected}, state) do
    game_screen = GameScreen.add_line(state.game_screen, "[Disconnected]", state.viewport_height)

    state =
      state
      |> Map.put(:connected, false)
      |> Map.put(:status_message, "Disconnected | Use /connect to reconnect")
      |> Map.put(:game_screen, game_screen)

    {state, []}
  end

  def handle_info({:event, :connection, {:error, reason}}, state) do
    error_msg = format_connection_error(reason)

    game_screen =
      state.game_screen
      |> GameScreen.add_line("[Connection error: #{inspect(reason)}]", state.viewport_height)
      |> GameScreen.add_line("[#{error_msg}]", state.viewport_height)

    state =
      state
      |> Map.put(:status_message, "Connection failed: #{error_msg}")
      |> Map.put(:game_screen, game_screen)

    {state, []}
  end

  def handle_info({:event, :state_changed, {:vitals, vitals}}, state) do
    game_screen = GameScreen.update_vitals(state.game_screen, vitals)
    {%{state | game_screen: game_screen}, []}
  end

  def handle_info({:event, :state_changed, {:room, room}}, state) do
    game_screen = GameScreen.update_room(state.game_screen, room)
    {%{state | game_screen: game_screen}, []}
  end

  # Handle log buffer updates for dog screen
  def handle_info({:log_update, lines}, state) do
    log_lines = Enum.reverse(lines)

    debug_screen =
      DebugScreen.update_logs(state.debug_screen, log_lines, state.term_height, @reserved_lines)

    {%{state | debug_screen: debug_screen}, []}
  end

  def handle_info(_msg, state) do
    {state, []}
  end

  def view(state) do
    stack(:vertical, [
      render_header(state),
      render_screen_tabs(state),
      render_screen_content(state),
      text(""),
      render_input(state),
      render_status_bar(state)
    ])
  end

  # ----------------------------------------------------------------------------
  # Screen Renderers
  # ----------------------------------------------------------------------------

  defp render_screen_content(state) do
    case state.current_screen do
      :game ->
        stack(:vertical, [
          GameScreen.render_vitals(state.game_screen),
          GameScreen.render_viewport(state.game_screen, state.viewport_height, state.term_width)
        ])

      :dog ->
        DebugScreen.render(
          state.debug_screen,
          state.term_height,
          state.term_width,
          @reserved_lines
        )

      :cat ->
        InfoScreen.render(state.info_screen)
    end
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

  # ----------------------------------------------------------------------------
  # Private Helpers
  # ----------------------------------------------------------------------------

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
            if state.debug_screen.scroll.auto_scroll,
              do: "Live",
              else: "Paused (scroll down to resume)"

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
    max(term_height - @reserved_lines, 5)
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
