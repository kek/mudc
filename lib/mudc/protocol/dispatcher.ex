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

  # Telnet option constants for guards
  @opt_gmcp 201
  @opt_suppress_go_ahead 3
  @opt_echo 1
  @opt_terminal_type 24
  @opt_window_size 31

  defstruct [:buffer, :socket_pid]

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
      socket_pid: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process, data}, _from, state) do
    # Combine with any buffered data
    combined = state.buffer <> data

    # Parse through Telnet parser
    {:ok, events, remaining} = TelnetParser.parse(combined)

    # Process each event and collect responses
    responses = Enum.flat_map(events, &dispatch_event/1)

    # Combine all responses
    response_data =
      if responses == [] do
        nil
      else
        Enum.join(responses)
      end

    {:reply, response_data, %{state | buffer: remaining}}
  end

  @impl true
  def handle_cast({:set_socket, pid}, state) do
    {:noreply, %{state | socket_pid: pid}}
  end

  # Dispatch individual events

  defp dispatch_event({:text, text}) do
    Bus.publish(:game_text, {:text, text})
    []
  end

  defp dispatch_event({:will, option}) do
    Logger.debug("WILL #{TC.option_name(option)}")
    handle_will(option)
  end

  defp dispatch_event({:wont, option}) do
    Logger.debug("WONT #{TC.option_name(option)}")
    handle_wont(option)
  end

  defp dispatch_event({:do, option}) do
    Logger.debug("DO #{TC.option_name(option)}")
    handle_do(option)
  end

  defp dispatch_event({:dont, option}) do
    Logger.debug("DONT #{TC.option_name(option)}")
    handle_dont(option)
  end

  defp dispatch_event({:subneg, option, data}) do
    Logger.debug("Subneg #{TC.option_name(option)}: #{byte_size(data)} bytes")
    handle_subneg(option, data)
  end

  defp dispatch_event({:ga}) do
    # Go Ahead - can be used for prompt detection
    Bus.publish(:game_text, :prompt)
    []
  end

  defp dispatch_event({:nop}) do
    # No operation - ignore
    []
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
end
