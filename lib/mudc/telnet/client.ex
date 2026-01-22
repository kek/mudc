defmodule Mudc.Telnet.Client do
  @moduledoc """
  GenServer managing a Telnet TCP connection.

  Handles connection lifecycle, sends commands, receives data,
  and communicates with the UI process.
  """

  use GenServer
  require Logger

  alias Mudc.Telnet.{ConnectionConfig, Protocol}

  @type state :: %{
          socket: :gen_tcp.socket() | nil,
          config: ConnectionConfig.t(),
          buffer: binary(),
          status: :disconnected | :connecting | :connected,
          ui_pid: pid() | nil
        }

  # Client API

  @doc """
  Starts the Telnet client GenServer.

  ## Options

  - `:ui_pid` - PID of the UI process to send output to
  - `:host` - Host to connect to (default: "172.24.0.1")
  - `:port` - Port to connect to (default: 4242)
  - `:timeout` - Connection timeout in ms (default: 5000)
  - `:name` - Process name (default: __MODULE__)

  ## Examples

      {:ok, pid} = Mudc.Telnet.Client.start_link(ui_pid: self())
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a command to the MUD server.

  Automatically appends CRLF (\\r\\n) to the command.

  ## Examples

      Mudc.Telnet.Client.send_command("look")
      Mudc.Telnet.Client.send_command("north")
  """
  @spec send_command(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def send_command(command, server \\ __MODULE__) do
    GenServer.call(server, {:send_command, command})
  end

  @doc """
  Gets the current connection status.
  """
  @spec status(GenServer.server()) :: :disconnected | :connecting | :connected
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc """
  Disconnects from the server.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(server \\ __MODULE__) do
    GenServer.call(server, :disconnect)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    ui_pid = Keyword.get(opts, :ui_pid)

    config_opts =
      opts
      |> Keyword.take([:host, :port, :timeout, :active])

    config = ConnectionConfig.new(config_opts)

    state = %{
      socket: nil,
      config: config,
      buffer: "",
      status: :disconnected,
      ui_pid: ui_pid
    }

    Logger.info("Telnet client starting, will connect to #{config.host}:#{config.port}")

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, new_state} ->
        notify_ui(new_state, {:connection_status, :connected})
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        notify_ui(state, {:connection_status, :failed, reason})
        # Crash and let supervisor restart
        {:stop, {:connection_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:send_command, _command}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:send_command, command}, _from, %{socket: socket} = state) do
    data = Protocol.encode(command <> "\r\n")

    case :gen_tcp.send(socket, data) do
      :ok ->
        Logger.debug("Sent command: #{command}")
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to send command: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:disconnect, _from, state) do
    new_state = close_connection(state)
    {:reply, :ok, %{new_state | status: :disconnected}}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    Logger.debug("Received #{byte_size(data)} bytes")

    # Decode Telnet protocol
    %{text: text, commands: commands} = Protocol.decode(data)

    # Handle any Telnet negotiations
    Enum.each(commands, fn cmd ->
      Logger.debug("Telnet command: #{inspect(cmd)}")

      case Protocol.handle_negotiation(cmd) do
        nil ->
          :ok

        response ->
          response_data = Protocol.encode_command(response)
          :gen_tcp.send(socket, response_data)
          Logger.debug("Sent negotiation response: #{inspect(response)}")
      end
    end)

    # Send text output to UI
    if text != "" do
      notify_ui(state, {:mud_output, text})
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("Connection closed by server")
    notify_ui(state, {:connection_status, :closed})
    # Crash and let supervisor restart
    {:stop, :connection_closed, state}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("TCP error: #{inspect(reason)}")
    notify_ui(state, {:connection_status, :error, reason})
    # Crash and let supervisor restart
    {:stop, {:tcp_error, reason}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Telnet client terminating: #{inspect(reason)}")
    close_connection(state)
    :ok
  end

  # Private Functions

  defp connect(%{config: config} = state) do
    host = to_charlist(config.host)
    port = config.port
    timeout = config.timeout

    opts = [
      :binary,
      packet: :raw,
      active: true,
      reuseaddr: true
    ]

    Logger.info("Connecting to #{config.host}:#{port}...")

    case :gen_tcp.connect(host, port, opts, timeout) do
      {:ok, socket} ->
        Logger.info("Connected successfully")
        {:ok, %{state | socket: socket, status: :connected}}

      {:error, reason} = error ->
        Logger.error("Connection failed: #{inspect(reason)}")
        error
    end
  end

  defp close_connection(%{socket: nil} = state), do: state

  defp close_connection(%{socket: socket} = state) do
    :gen_tcp.close(socket)
    %{state | socket: nil}
  end

  defp notify_ui(%{ui_pid: nil}, _msg), do: :ok

  defp notify_ui(%{ui_pid: pid}, msg) when is_pid(pid) do
    send(pid, msg)
    :ok
  end
end
