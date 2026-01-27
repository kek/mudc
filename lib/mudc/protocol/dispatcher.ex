defmodule Mudc.Protocol.Dispatcher do
  @moduledoc """
  Routes parsed Telnet data to appropriate handlers.

  Receives raw TCP data, parses it through the Telnet parser,
  and dispatches events:
  - Text goes to the event bus for UI
  - GMCP subnegotiations go to the GMCP handler
  - Other Telnet negotiations are handled (WILL/DO/WONT/DONT)
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.Events.Bus
  alias Mudc.Network.Telnet.Parser, as: TelnetParser
  alias Mudc.Network.Telnet.Constants, as: TC
  alias Mudc.Network.GMCP.Handler, as: GMCPHandler
  alias Mudc.Prompt

  # Telnet option constants for guards (from TC module)
  @opt_gmcp TC.opt_gmcp()
  @opt_suppress_go_ahead TC.opt_suppress_go_ahead()
  @opt_echo TC.opt_echo()
  @opt_terminal_type TC.opt_terminal_type()
  @opt_window_size TC.opt_window_size()

  defstruct [:buffer, :socket_pid, :last_text]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Process raw TCP data.
  Returns any data that should be sent back to the server.
  """
  def process_data(data) do
    GenServer.call(__MODULE__, {:process, data})
  end

  @doc """
  Set the socket PID for sending responses.
  """
  def set_socket(socket_pid) do
    GenServer.cast(__MODULE__, {:set_socket, socket_pid})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      buffer: <<>>,
      socket_pid: nil,
      last_text: ""
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process, data}, _from, state) do
    # Combine with any buffered data
    combined = state.buffer <> data

    # Parse through Telnet parser
    {:ok, events, remaining} = TelnetParser.parse(combined)

    # Process each event and collect responses, threading state through
    {responses, new_state} =
      Enum.reduce(events, {[], state}, fn event, {acc_responses, acc_state} ->
        {event_responses, updated_state} = dispatch_event(event, acc_state)
        {acc_responses ++ event_responses, updated_state}
      end)

    # Combine all responses
    response_data =
      if responses == [] do
        nil
      else
        Enum.join(responses)
      end

    {:reply, response_data, %{new_state | buffer: remaining}}
  end

  @impl true
  def handle_cast({:set_socket, pid}, state) do
    {:noreply, %{state | socket_pid: pid}}
  end

  # Dispatch individual events

  defp dispatch_event({:text, text}, state) do
    # Ensure text is valid UTF-8, replacing invalid sequences
    valid_text = scrub_utf8(text)

    # If we have buffered text (potential prompt), publish it now as regular text
    # since new text arrived (means it wasn't a prompt)
    if state.last_text != "" do
      Bus.publish(:game_text, {:text, state.last_text})
    end

    # Split into lines to handle mixed content (game text + prompt on last line)
    lines = String.split(valid_text, "\n")

    cond do
      # Text ends with newline - all lines are complete game text
      String.ends_with?(valid_text, "\n") ->
        Bus.publish(:game_text, {:text, valid_text})
        {[], %{state | last_text: ""}}

      # Single line without newline - check if it's a prompt
      length(lines) == 1 ->
        last_line = hd(lines)

        if Prompt.is_prompt?(last_line) do
          # It's a prompt - publish immediately
          Bus.publish(:game_text, {:prompt, last_line})
          {[], %{state | last_text: ""}}
        else
          # Not a prompt - buffer it (might be incomplete text or waiting for GA)
          {[], %{state | last_text: last_line}}
        end

      # Multiple lines - publish all complete lines as text, check last line
      true ->
        complete_lines = Enum.slice(lines, 0..-2//1)
        last_line = List.last(lines)

        # Publish all complete lines as game text
        if complete_lines != [] do
          complete_text = Enum.join(complete_lines, "\n") <> "\n"
          Bus.publish(:game_text, {:text, complete_text})
        end

        # Check if last line is a prompt
        if Prompt.is_prompt?(last_line) do
          Bus.publish(:game_text, {:prompt, last_line})
          {[], %{state | last_text: ""}}
        else
          # Buffer the last line
          {[], %{state | last_text: last_line}}
        end
    end
  end

  defp dispatch_event({:will, option}, state) do
    Logger.debug("WILL #{TC.option_name(option)}")
    {handle_will(option), state}
  end

  defp dispatch_event({:wont, option}, state) do
    Logger.debug("WONT #{TC.option_name(option)}")
    {handle_wont(option), state}
  end

  defp dispatch_event({:do, option}, state) do
    Logger.debug("DO #{TC.option_name(option)}")
    {handle_do(option), state}
  end

  defp dispatch_event({:dont, option}, state) do
    Logger.debug("DONT #{TC.option_name(option)}")
    {handle_dont(option), state}
  end

  defp dispatch_event({:subneg, option, data}, state) do
    Logger.debug("Subneg #{TC.option_name(option)}: #{byte_size(data)} bytes")
    {handle_subneg(option, data), state}
  end

  defp dispatch_event({:ga}, state) do
    # Go Ahead - check if buffered text is an actual prompt
    if Prompt.is_prompt?(state.last_text) do
      # This looks like a prompt - send to input line
      Bus.publish(:game_text, {:prompt, state.last_text})
    else
      # Not a prompt pattern - send to game output as regular text
      if state.last_text != "" do
        Bus.publish(:game_text, {:text, state.last_text})
      end
    end

    {[], %{state | last_text: ""}}
  end

  defp dispatch_event({:nop}, state) do
    # No operation - ignore
    {[], state}
  end

  # Handle WILL negotiations

  defp handle_will(opt) when opt == @opt_gmcp do
    case GMCPHandler.handle_negotiation({:will, opt}) do
      {:ok, response} -> [response]
      :ok -> []
      :ignore -> []
    end
  end

  defp handle_will(opt) when opt == @opt_suppress_go_ahead do
    # Accept suppress go-ahead
    [TelnetParser.do_(opt)]
  end

  defp handle_will(opt) when opt == @opt_echo do
    # Accept echo (password mode)
    Bus.publish(:telnet, {:echo, true})
    [TelnetParser.do_(opt)]
  end

  defp handle_will(_opt) do
    # Reject unknown options
    []
  end

  # Handle WONT negotiations

  defp handle_wont(opt) when opt == @opt_gmcp do
    GMCPHandler.handle_negotiation({:wont, opt})
    []
  end

  defp handle_wont(opt) when opt == @opt_echo do
    Bus.publish(:telnet, {:echo, false})
    []
  end

  defp handle_wont(_opt) do
    []
  end

  # Handle DO negotiations

  defp handle_do(opt) when opt == @opt_gmcp do
    case GMCPHandler.handle_negotiation({:do, opt}) do
      {:ok, response} -> [response]
      :ok -> []
      :ignore -> []
    end
  end

  defp handle_do(opt) when opt == @opt_terminal_type do
    # We can provide terminal type
    [TelnetParser.will(opt)]
  end

  defp handle_do(opt) when opt == @opt_window_size do
    # We can provide window size (NAWS)
    [TelnetParser.will(opt)]
  end

  defp handle_do(_opt) do
    # Refuse unknown requests
    []
  end

  # Handle DONT negotiations

  defp handle_dont(opt) when opt == @opt_gmcp do
    GMCPHandler.handle_negotiation({:dont, opt})
    []
  end

  defp handle_dont(_opt) do
    []
  end

  # Handle subnegotiations

  defp handle_subneg(opt, data) when opt == @opt_gmcp do
    GMCPHandler.handle_subneg(data)
    []
  end

  defp handle_subneg(opt, _data) when opt == @opt_terminal_type do
    # Server is asking for terminal type
    # Format: IAC SB TERMINAL-TYPE IS <type> IAC SE
    term_type = Config.get(:protocol, :terminal_type) || "XTERM-256COLOR"
    response = TelnetParser.subnegotiation(opt, <<0>> <> term_type)
    [response]
  end

  defp handle_subneg(_opt, _data) do
    []
  end

  # Scrub invalid UTF-8 sequences from binary data
  # MUD servers may send invalid UTF-8 or latin-1, so we need to handle it gracefully
  defp scrub_utf8(binary) when is_binary(binary) do
    # First check if it's already valid UTF-8
    if String.valid?(binary) do
      binary
    else
      # Try to convert from latin-1 to UTF-8 first (common for older MUDs)
      case :unicode.characters_to_binary(binary, :latin1, :utf8) do
        result when is_binary(result) ->
          result

        _ ->
          # If that fails, scrub byte by byte
          Logger.debug("Invalid UTF-8/latin-1 sequence detected, scrubbing")
          scrub_byte_by_byte(binary)
      end
    end
  end

  # Replace invalid bytes with Unicode replacement character (U+FFFD)
  # This handles each byte individually, preserving valid UTF-8 sequences
  defp scrub_byte_by_byte(binary) do
    for <<byte <- binary>>, into: <<>> do
      cond do
        # ASCII is always valid
        byte < 128 ->
          <<byte>>

        # Try to interpret as latin-1 and convert to UTF-8
        true ->
          case :unicode.characters_to_binary(<<byte>>, :latin1, :utf8) do
            result when is_binary(result) -> result
            _ -> "�"
          end
      end
    end
  end
end
