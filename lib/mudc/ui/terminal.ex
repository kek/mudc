defmodule Mudc.UI.Terminal do
  @moduledoc """
  Terminal UI for the MUD client using TermUI.Elm architecture.

  Provides an interactive REPL-style interface with:
  - Scrollable output area for MUD responses
  - Command input line
  - Status bar for connection info
  """

  use TermUI.Elm
  require Logger

  @max_output_lines 1000

  # Elm Architecture Implementation

  @impl true
  def init(_opts) do
    # Start the Telnet client with reference to this UI process
    case Mudc.Telnet.Client.start_link(ui_pid: self()) do
      {:ok, _pid} ->
        Logger.info("Telnet client started from UI")

      {:error, {:already_started, _pid}} ->
        Logger.info("Telnet client already running")

      {:error, reason} ->
        Logger.error("Failed to start Telnet client: #{inspect(reason)}")
    end

    %{
      input: "",
      output_lines: [
        "╔═══════════════════════════════════════════════════════════╗",
        "║          MUDC - Multi-User Dungeon Client                ║",
        "║                    v0.1.0                                 ║",
        "╚═══════════════════════════════════════════════════════════╝",
        "",
        "Connecting to MMapper at 172.24.0.1:4242...",
        ""
      ],
      connection_status: :connecting,
      command_history: [],
      history_index: nil
    }
  end

  @impl true
  def update(msg, state) do
    case msg do
      {:char, char} when is_binary(char) ->
        # Add character to input
        {%{state | input: state.input <> char, history_index: nil}, []}

      :backspace ->
        # Remove last character from input
        new_input =
          if String.length(state.input) > 0 do
            String.slice(state.input, 0..-2//1)
          else
            state.input
          end

        {%{state | input: new_input, history_index: nil}, []}

      :submit_command ->
        handle_submit_command(state)

      {:mud_output, data} ->
        handle_mud_output(state, data)

      {:connection_status, status} ->
        handle_connection_status(state, status)

      {:connection_status, :failed, reason} ->
        handle_connection_failed(state, reason)

      {:connection_status, :error, reason} ->
        handle_connection_error(state, reason)

      :history_up ->
        navigate_history(state, :up)

      :history_down ->
        navigate_history(state, :down)

      :quit ->
        new_state = add_output(state, ["", "Disconnecting...", "Goodbye!"])
        {new_state, [:quit]}

      _ ->
        {state, []}
    end
  end

  @impl true
  def view(%{input: input, output_lines: lines, connection_status: status} = _state) do
    # Limit output lines to prevent memory issues
    display_lines = Enum.take(lines, -50)

    # Build the UI using TermUI helpers
    box(
      [
        # Status bar
        text(status_bar_text(status)),
        text(""),
        # Output area
        stack(
          :vertical,
          Enum.map(display_lines, &text/1)
        ),
        text(""),
        # Input area
        text("#{prompt_symbol(status)}#{input}")
      ]
    )
  end

  @impl true
  def event_to_msg(event, _state) do
    case event do
      %TermUI.Event.Key{key: :enter} ->
        {:msg, :submit_command}

      %TermUI.Event.Key{key: :backspace} ->
        {:msg, :backspace}

      %TermUI.Event.Key{key: :up} ->
        {:msg, :history_up}

      %TermUI.Event.Key{key: :down} ->
        {:msg, :history_down}

      %TermUI.Event.Key{key: {:ctrl, ?c}} ->
        {:msg, :quit}

      %TermUI.Event.Key{key: {:ctrl, ?d}} ->
        {:msg, :quit}

      %TermUI.Event.Key{char: char} when is_binary(char) and char != "" ->
        {:msg, {:char, char}}

      _ ->
        :ignore
    end
  end

  # Private Helper Functions

  defp handle_submit_command(%{input: input} = state) do
    cmd = String.trim(input)

    if cmd == "" do
      {state, []}
    else
      case cmd do
        "quit" ->
          update(:quit, state)

        "exit" ->
          update(:quit, state)

        _ ->
          # Send command to Telnet client
          case Mudc.Telnet.Client.send_command(cmd) do
            :ok ->
              new_state =
                state
                |> add_output(["> #{cmd}"])
                |> add_to_history(cmd)
                |> Map.put(:input, "")
                |> Map.put(:history_index, nil)

              {new_state, []}

            {:error, :not_connected} ->
              new_state =
                state
                |> add_output(["Error: Not connected to server"])
                |> Map.put(:input, "")

              {new_state, []}

            {:error, reason} ->
              new_state =
                state
                |> add_output(["Error: #{inspect(reason)}"])
                |> Map.put(:input, "")

              {new_state, []}
          end
      end
    end
  end

  defp handle_mud_output(state, data) do
    # Split data into lines and add to output
    lines =
      data
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))

    new_state = add_output(state, lines)
    {new_state, []}
  end

  defp handle_connection_status(state, :connected) do
    new_state =
      state
      |> add_output(["Connected successfully!", ""])
      |> Map.put(:connection_status, :connected)

    {new_state, []}
  end

  defp handle_connection_status(state, :closed) do
    new_state =
      state
      |> add_output(["", "Connection closed by server."])
      |> Map.put(:connection_status, :disconnected)

    {new_state, []}
  end

  defp handle_connection_failed(state, reason) do
    new_state =
      state
      |> add_output(["Connection failed: #{inspect(reason)}", ""])
      |> Map.put(:connection_status, :failed)

    {new_state, []}
  end

  defp handle_connection_error(state, reason) do
    new_state =
      state
      |> add_output(["Connection error: #{inspect(reason)}", ""])
      |> Map.put(:connection_status, :error)

    {new_state, []}
  end

  defp add_output(%{output_lines: lines} = state, new_lines) do
    updated_lines =
      (lines ++ new_lines)
      |> Enum.take(-@max_output_lines)

    %{state | output_lines: updated_lines}
  end

  defp add_to_history(%{command_history: history} = state, cmd) do
    # Add to history, limit to last 100 commands
    new_history =
      [cmd | history]
      |> Enum.take(100)

    %{state | command_history: new_history}
  end

  defp navigate_history(%{command_history: []} = state, _direction) do
    {state, []}
  end

  defp navigate_history(%{command_history: history, history_index: nil} = state, :up) do
    # Start navigating history from most recent
    cmd = List.first(history)
    {%{state | input: cmd, history_index: 0}, []}
  end

  defp navigate_history(%{history_index: nil} = state, :down) do
    # Already at current input, do nothing
    {state, []}
  end

  defp navigate_history(%{command_history: history, history_index: index} = state, :up) do
    # Go to older command
    max_index = length(history) - 1

    if index < max_index do
      new_index = index + 1
      cmd = Enum.at(history, new_index)
      {%{state | input: cmd, history_index: new_index}, []}
    else
      {state, []}
    end
  end

  defp navigate_history(%{command_history: history, history_index: index} = state, :down)
       when index > 0 do
    # Go to newer command
    new_index = index - 1
    cmd = Enum.at(history, new_index)
    {%{state | input: cmd, history_index: new_index}, []}
  end

  defp navigate_history(state, :down) do
    # Back to current input (clear)
    {%{state | input: "", history_index: nil}, []}
  end

  defp status_bar_text(:connected) do
    "┌─ Status: Connected ──────────────────────────────────────┐"
  end

  defp status_bar_text(:connecting) do
    "┌─ Status: Connecting... ──────────────────────────────────┐"
  end

  defp status_bar_text(:disconnected) do
    "┌─ Status: Disconnected ───────────────────────────────────┐"
  end

  defp status_bar_text(:failed) do
    "┌─ Status: Connection Failed ─────────────────────────────┐"
  end

  defp status_bar_text(:error) do
    "┌─ Status: Error ──────────────────────────────────────────┐"
  end

  defp status_bar_text(_) do
    "┌─ Status: Unknown ────────────────────────────────────────┐"
  end

  defp prompt_symbol(:connected), do: "> "
  defp prompt_symbol(:connecting), do: "⋯ "
  defp prompt_symbol(:disconnected), do: "✗ "
  defp prompt_symbol(:failed), do: "✗ "
  defp prompt_symbol(:error), do: "✗ "
  defp prompt_symbol(_), do: "? "
end
