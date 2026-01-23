defmodule Mudc.Network.Connection do
  @moduledoc """
  GenServer managing the TCP connection to the MUD server (via MMapper).

  Uses `active: :once` mode to prevent socket flooding and enable backpressure.
  Publishes received data to the event bus for processing by other components.
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.Events.Bus
  alias Mudc.Protocol.Dispatcher

  @default_host ~c"localhost"
  @default_port 23

  defstruct [:socket, :host, :port, :connected]

  # Client API

  @doc """
  Starts the connection GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connects to the MUD server.
  """
  def connect(host \\ @default_host, port \\ @default_port) do
    GenServer.call(__MODULE__, {:connect, host, port})
  end

  @doc """
  Disconnects from the MUD server.
  """
  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Sends a command to the MUD server.
  """
  def send_command(command) do
    GenServer.call(__MODULE__, {:send, command})
  end

  @doc """
  Returns the current connection status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Read from config, with opts overriding config values
    config_host = System.get_env("MUD_HOST") || Config.get(:connection, :host) || "localhost"
    config_port = parse_env_port("MUD_PORT") || Config.get(:connection, :port) || @default_port
    config_auto_connect = Config.get(:connection, :auto_connect) || false

    host = Keyword.get(opts, :host, to_charlist(config_host))
    port = Keyword.get(opts, :port, config_port)
    auto_connect = Keyword.get(opts, :auto_connect, config_auto_connect)

    state = %__MODULE__{
      socket: nil,
      host: host,
      port: port,
      connected: false
    }

    # Auto-connect if configured
    if auto_connect do
      send(self(), :auto_connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, host, port}, _from, state) do
    case do_connect(host, port) do
      {:ok, socket} ->
        Logger.info("Connected to #{host}:#{port}")
        Bus.publish(:connection, {:connected, host, port})
        new_state = %{state | socket: socket, host: host, port: port, connected: true}
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to connect to #{host}:#{port}: #{inspect(reason)}")
        Bus.publish(:connection, {:error, reason})
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, %{socket: nil} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:disconnect, _from, %{socket: socket} = state) do
    :gen_tcp.close(socket)
    Logger.info("Disconnected")
    Bus.publish(:connection, :disconnected)
    {:reply, :ok, %{state | socket: nil, connected: false}}
  end

  @impl true
  def handle_call({:send, _command}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:send, command}, _from, %{socket: socket} = state) do
    # Append newline if not present
    data =
      if String.ends_with?(command, "\n") do
        command
      else
        command <> "\n"
      end

    case :gen_tcp.send(socket, data) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Send failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      connected: state.connected,
      host: state.host,
      port: state.port
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:auto_connect, state) do
    case do_connect(state.host, state.port) do
      {:ok, socket} ->
        Logger.info("Auto-connected to #{state.host}:#{state.port}")
        Bus.publish(:connection, {:connected, state.host, state.port})
        {:noreply, %{state | socket: socket, connected: true}}

      {:error, reason} ->
        Logger.warning("Auto-connect failed: #{inspect(reason)}, retrying in 5s")
        Bus.publish(:connection, {:error, reason})
        Process.send_after(self(), :auto_connect, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    # Re-arm the socket for the next message
    :inet.setopts(socket, active: :once)

    # Process through the protocol dispatcher
    # This parses Telnet and publishes events to the bus
    case Dispatcher.process_data(data) do
      nil ->
        :ok

      response when is_binary(response) ->
        # Send any protocol responses back to the server
        :gen_tcp.send(socket, response)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.info("Connection closed by server")
    Bus.publish(:connection, :disconnected)
    {:noreply, %{state | socket: nil, connected: false}}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("TCP error: #{inspect(reason)}")
    Bus.publish(:connection, {:error, reason})
    :gen_tcp.close(socket)
    {:noreply, %{state | socket: nil, connected: false}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp parse_env_port(var) do
    case System.get_env(var) do
      nil -> nil
      str -> String.to_integer(str)
    end
  end

  defp do_connect(host, port) do
    # Ensure host is a charlist for :gen_tcp
    host_charlist =
      cond do
        is_binary(host) -> String.to_charlist(host)
        is_list(host) -> host
        true -> to_charlist(host)
      end

    opts = [
      :binary,
      active: :once,
      packet: :raw,
      nodelay: true
    ]

    :gen_tcp.connect(host_charlist, port, opts, 5000)
  end
end
