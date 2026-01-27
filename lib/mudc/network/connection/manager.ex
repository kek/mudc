defmodule Mudc.Network.Connection.Manager do
  @moduledoc """
  Connection lifecycle manager.

  Manages connection state, auto-connect, and reconnection logic.
  Supervises the Socket worker and can restart it on crashes.

  Socket crashes don't lose connection parameters - Manager remembers
  host/port and can reconnect.
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.ErrorHandler
  alias Mudc.Events.Bus
  alias Mudc.Network.Connection.Socket

  defstruct [:socket_pid, :host, :port, :connected, :auto_reconnect]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connect to the MUD server.
  Uses configured defaults if not specified.
  """
  def connect(host \\ nil, port \\ nil) do
    GenServer.call(__MODULE__, {:connect, host, port})
  end

  @doc """
  Disconnect from the MUD server.
  """
  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Send a command to the MUD server.
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
    config_port = parse_env_port("MUD_PORT") || Config.get(:connection, :port) || 4242
    config_auto_connect = Config.get(:connection, :auto_connect) || false

    host = Keyword.get(opts, :host, to_charlist(config_host))
    port = Keyword.get(opts, :port, config_port)
    auto_connect = Keyword.get(opts, :auto_connect, config_auto_connect)

    state = %__MODULE__{
      socket_pid: nil,
      host: host,
      port: port,
      connected: false,
      auto_reconnect: false
    }

    # Auto-connect if configured
    if auto_connect do
      send(self(), :auto_connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, host, port}, _from, state) do
    # Use state defaults if not provided
    connect_host = host || state.host
    connect_port = port || state.port

    case start_socket_and_connect(connect_host, connect_port) do
      {:ok, socket_pid} ->
        Logger.info("Connected to #{connect_host}:#{connect_port}")
        Bus.publish(:connection, {:connected, connect_host, connect_port})

        new_state = %{
          state
          | socket_pid: socket_pid,
            host: connect_host,
            port: connect_port,
            connected: true
        }

        {:reply, :ok, new_state}

      {:error, reason} = error ->
        ErrorHandler.connection_error(
          "Failed to connect",
          reason,
          %{host: connect_host, port: connect_port}
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, %{socket_pid: nil} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:disconnect, _from, %{socket_pid: socket_pid} = state) do
    Socket.close(socket_pid)
    stop_socket(socket_pid)

    Logger.info("Disconnected")
    Bus.publish(:connection, :disconnected)

    {:reply, :ok, %{state | socket_pid: nil, connected: false, auto_reconnect: false}}
  end

  @impl true
  def handle_call({:send, _command}, _from, %{socket_pid: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:send, command}, _from, %{socket_pid: socket_pid} = state) do
    # Log user input
    Logger.info("User input: #{String.trim(command)}")

    # Publish user input event for logging to file
    Bus.publish(:user_input, {:command, command})

    # Append newline if not present
    data =
      if String.ends_with?(command, "\n") do
        command
      else
        command <> "\n"
      end

    case Socket.send_data(socket_pid, data) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} = error ->
        ErrorHandler.log_error("Send command failed", reason)
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
    case start_socket_and_connect(state.host, state.port) do
      {:ok, socket_pid} ->
        Logger.info("Auto-connected to #{state.host}:#{state.port}")
        Bus.publish(:connection, {:connected, state.host, state.port})
        {:noreply, %{state | socket_pid: socket_pid, connected: true, auto_reconnect: true}}

      {:error, reason} ->
        ErrorHandler.retry_warning(
          "Auto-connect failed",
          reason,
          5000,
          %{host: state.host, port: state.port}
        )

        Bus.publish(:connection, {:error, reason})
        delay = Config.get(:connection, :auto_reconnect_delay_ms) || 5000
        Process.send_after(self(), :auto_connect, delay)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:socket_closed, _socket_pid}, state) do
    Logger.info("Socket closed by server")
    Bus.publish(:connection, :disconnected)

    new_state = %{state | socket_pid: nil, connected: false}

    # Auto-reconnect if enabled
    if state.auto_reconnect do
      delay = Config.get(:connection, :auto_reconnect_delay_ms) || 5000
      Process.send_after(self(), :auto_connect, delay)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:socket_error, _socket_pid, reason}, state) do
    ErrorHandler.connection_error("TCP error", reason)
    Bus.publish(:connection, {:error, reason})

    new_state = %{state | socket_pid: nil, connected: false}

    # Auto-reconnect if enabled
    if state.auto_reconnect do
      delay = Config.get(:connection, :auto_reconnect_delay_ms) || 5000
      Process.send_after(self(), :auto_connect, delay)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, socket_pid, reason}, %{socket_pid: socket_pid} = state) do
    Logger.warning("Socket process crashed: #{inspect(reason)}")
    Bus.publish(:connection, :disconnected)

    new_state = %{state | socket_pid: nil, connected: false}

    # Auto-reconnect if enabled
    if state.auto_reconnect do
      delay = Config.get(:connection, :auto_reconnect_delay_ms) || 5000
      Process.send_after(self(), :auto_connect, delay)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Manager: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.socket_pid do
      stop_socket(state.socket_pid)
    end

    :ok
  end

  # Private Functions

  defp parse_env_port(var) do
    case System.get_env(var) do
      nil -> nil
      str -> String.to_integer(str)
    end
  end

  defp start_socket_and_connect(host, port) do
    # Start Socket worker
    case Socket.start_link(manager_pid: self(), host: host, port: port) do
      {:ok, socket_pid} ->
        # Monitor the socket process
        Process.monitor(socket_pid)

        # Connect the socket
        case Socket.connect(socket_pid, host, port) do
          {:ok, _socket} ->
            {:ok, socket_pid}

          {:error, reason} ->
            # Stop the socket worker if connection fails
            stop_socket(socket_pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_socket(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :normal)
    end
  end
end
