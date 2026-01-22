defmodule Mudc.UI.App do
  @moduledoc """
  Main terminal UI for the MUD client using term_ui's Elm Architecture.

  Features:
  - Scrollable viewport for game text
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

  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Widgets.TextInput, as: TI
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection

  @max_lines 1000
  @viewport_height 20

  # ----------------------------------------------------------------------------
  # Component Callbacks
  # ----------------------------------------------------------------------------

  def init(_opts) do
    # Subscribe to events from other components
    Bus.subscribe(:game_text)
    Bus.subscribe(:connection)
    Bus.subscribe(:state_changed)

    # Create text input for commands
    input_props =
      TI.new(
        placeholder: "Enter command...",
        width: 78
      )

    {:ok, input_state} = TI.init(input_props)

    %{
      # Game text lines (newest at the end)
      lines: [],
      scroll_offset: 0,
      auto_scroll: true,

      # Command input
      input: TI.set_focused(input_state, true),

      # Command history
      history: [],
      history_index: nil,

      # Connection status
      connected: false,
      status_message: "Not connected",

      # GMCP data
      vitals: %{},
      room: %{}
    }
  end

  def event_to_msg(%Event.Key{key: :enter}, state) do
    command = TI.get_value(state.input)
    {:msg, {:send_command, command}}
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

  def event_to_msg(%Event.Key{key: :home} = event, _state) do
    if Event.has_modifier?(event, :ctrl) do
      {:msg, :scroll_top}
    else
      {:msg, {:input_event, event}}
    end
  end

  def event_to_msg(%Event.Key{key: :end} = event, _state) do
    if Event.has_modifier?(event, :ctrl) do
      {:msg, :scroll_bottom}
    else
      {:msg, {:input_event, event}}
    end
  end

  def event_to_msg(%Event.Key{key: "c"} = event, _state) do
    if Event.has_modifier?(event, :ctrl) do
      {:msg, :quit}
    else
      {:msg, {:input_event, event}}
    end
  end

  def event_to_msg(event, _state) do
    {:msg, {:input_event, event}}
  end

  def update({:send_command, ""}, state) do
    # Empty command, do nothing
    {state, []}
  end

  def update({:send_command, command}, state) do
    # Send command to server
    case Connection.send_command(command) do
      :ok ->
        # Add to history and clear input
        history = [command | state.history] |> Enum.take(100)
        input = TI.clear(state.input)

        {%{state | input: input, history: history, history_index: nil}, []}

      {:error, :not_connected} ->
        new_state = add_local_line(state, "[Not connected - use /connect to connect]")
        {new_state, []}

      {:error, reason} ->
        new_state = add_local_line(state, "[Send error: #{inspect(reason)}]")
        {new_state, []}
    end
  end

  def update(:history_prev, state) do
    new_index =
      case state.history_index do
        nil -> 0
        idx -> min(idx + 1, length(state.history) - 1)
      end

    command = Enum.at(state.history, new_index, "")
    input = TI.set_value(state.input, command)
    {%{state | input: input, history_index: new_index}, []}
  end

  def update(:history_next, state) do
    case state.history_index do
      nil ->
        {state, []}

      0 ->
        input = TI.clear(state.input)
        {%{state | input: input, history_index: nil}, []}

      idx ->
        new_index = idx - 1
        command = Enum.at(state.history, new_index, "")
        input = TI.set_value(state.input, command)
        {%{state | input: input, history_index: new_index}, []}
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

  def update({:input_event, event}, state) do
    {:ok, new_input} = TI.handle_event(event, state.input)
    {%{state | input: new_input}, []}
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update(:connect, state) do
    Connection.connect()
    {state, []}
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

  def handle_info(_msg, state) do
    {state, []}
  end

  def view(state) do
    stack(:vertical, [
      render_header(state),
      render_vitals_bar(state),
      render_viewport(state),
      text(""),
      render_input(state),
      render_status_bar(state)
    ])
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
        # Truncate long lines
        truncated = String.slice(line, 0, 78)
        text(truncated)
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

    stack(:vertical, [
      stack(:horizontal, [
        text("> ", border_style),
        TI.render(state.input, %{width: 76, height: 1})
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
