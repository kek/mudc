defmodule Mudc.Network.GMCP.Handler do
  @moduledoc """
  GenServer for processing GMCP messages.

  Receives parsed GMCP subnegotiations from the protocol dispatcher,
  decodes them, and publishes the data to the event bus.

  Also handles GMCP-related Telnet negotiations (WILL/DO GMCP).
  """

  use GenServer
  require Logger

  alias Mudc.ErrorHandler
  alias Mudc.Events.Bus
  alias Mudc.Network.GMCP.Parser
  alias Mudc.Network.GMCP.Negotiation

  # GMCP option constant for guards
  @opt_gmcp 201

  defstruct [:enabled, :supported_packages]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handle a Telnet negotiation event related to GMCP.
  Returns `{:ok, response_data}` or `:ok` if no response needed.
  """
  def handle_negotiation(event) do
    GenServer.call(__MODULE__, {:negotiation, event})
  end

  @doc """
  Handle a GMCP subnegotiation message.
  """
  def handle_subneg(data) do
    GenServer.cast(__MODULE__, {:subneg, data})
  end

  @doc """
  Send a GMCP message to the server.
  Returns the binary data to send.
  """
  def send_message(package, data \\ nil) do
    GenServer.call(__MODULE__, {:send, package, data})
  end

  @doc """
  Check if GMCP is enabled.
  """
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      enabled: false,
      supported_packages: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:negotiation, {:will, opt}}, _from, state)
      when opt == @opt_gmcp do
    Logger.info("Server offers GMCP, sending handshake")
    response = Negotiation.initial_handshake()
    new_state = %{state | enabled: true}
    Bus.publish(:gmcp, :enabled)
    {:reply, {:ok, response}, new_state}
  end

  @impl true
  def handle_call({:negotiation, {:do, opt}}, _from, state)
      when opt == @opt_gmcp do
    # Server is asking us to enable GMCP (less common)
    Logger.info("Server requests GMCP")
    response = Negotiation.initial_handshake()
    new_state = %{state | enabled: true}
    Bus.publish(:gmcp, :enabled)
    {:reply, {:ok, response}, new_state}
  end

  @impl true
  def handle_call({:negotiation, {:wont, opt}}, _from, state)
      when opt == @opt_gmcp do
    Logger.info("Server disabled GMCP")
    new_state = %{state | enabled: false}
    Bus.publish(:gmcp, :disabled)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:negotiation, {:dont, opt}}, _from, state)
      when opt == @opt_gmcp do
    Logger.info("Server rejected GMCP")
    new_state = %{state | enabled: false}
    Bus.publish(:gmcp, :disabled)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:negotiation, _event}, _from, state) do
    # Not a GMCP negotiation
    {:reply, :ignore, state}
  end

  @impl true
  def handle_call({:send, package, data}, _from, state) do
    if state.enabled do
      message = Parser.encode(package, data)
      response = Negotiation.wrap_subneg(message)
      {:reply, {:ok, response}, state}
    else
      {:reply, {:error, :gmcp_not_enabled}, state}
    end
  end

  @impl true
  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  @impl true
  def handle_cast({:subneg, data}, state) do
    case Parser.parse(data) do
      {:ok, package, payload} ->
        Logger.debug("GMCP: #{package} -> #{inspect(payload)}")
        Bus.publish(:gmcp, {:message, package, payload})
        handle_gmcp_message(package, payload)

      {:error, reason} ->
        ErrorHandler.log_warning("Failed to parse GMCP message", reason)
    end

    {:noreply, state}
  end

  # Handle specific GMCP messages
  defp handle_gmcp_message("Char.Vitals", data) do
    Bus.publish(:gmcp_vitals, data)
  end

  defp handle_gmcp_message("Room.Info", data) do
    Bus.publish(:gmcp_room, data)
  end

  defp handle_gmcp_message("Comm.Channel" <> _, data) do
    Bus.publish(:gmcp_channel, data)
  end

  defp handle_gmcp_message("Char.Status", data) do
    Bus.publish(:gmcp_status, data)
  end

  defp handle_gmcp_message("Core.Goodbye", _data) do
    Logger.info("Server sent Core.Goodbye")
  end

  defp handle_gmcp_message(_package, _data) do
    # Unknown package, already published to :gmcp topic
    :ok
  end
end
