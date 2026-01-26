defmodule Mudc.Network.Connection.Socket do
  @moduledoc """
  TCP socket I/O worker.

  Handles low-level socket operations: connecting, sending, receiving data.
  If this process crashes, the Manager can spawn a new Socket with the same
  connection parameters.

  This separation means socket crashes don't lose connection state.
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.Protocol.Dispatcher

  defstruct [:socket, :host, :port, :manager_pid]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Connect to a TCP server.
  """
  def connect(pid, host, port) do
    GenServer.call(pid, {:connect, host, port})
  end

  @doc """
  Send data over the socket.
  """
  def send_data(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  @doc """
  Close the socket.
  """
  def close(pid) do
    GenServer.call(pid, :close)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    manager_pid = Keyword.fetch!(opts, :manager_pid)
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port)

    state = %__MODULE__{
      socket: nil,
      host: host,
      port: port,
      manager_pid: manager_pid
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, host, port}, _from, state) do
    case do_connect(host, port) do
      {:ok, socket} ->
        Logger.info("Socket connected to #{host}:#{port}")
        new_state = %{state | socket: socket, host: host, port: port}
        {:reply, {:ok, socket}, new_state}

      {:error, reason} = error ->
        Logger.error("Socket connection failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:send, _data}, _from, %{socket: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:send, data}, _from, %{socket: socket} = state) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Socket send failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:close, _from, %{socket: nil} = state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:close, _from, %{socket: socket} = state) do
    :gen_tcp.close(socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    # Re-arm the socket for the next message
    :inet.setopts(socket, active: :once)

    # Process through the protocol dispatcher
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
    Logger.info("Socket closed by server")
    # Notify manager
    send(state.manager_pid, {:socket_closed, self()})
    {:noreply, %{state | socket: nil}}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("Socket error: #{inspect(reason)}")
    :gen_tcp.close(socket)
    # Notify manager
    send(state.manager_pid, {:socket_error, self(), reason})
    {:noreply, %{state | socket: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Socket: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end

    :ok
  end

  # Private Functions

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

    timeout = Config.get(:connection, :timeout_ms) || 5000
    :gen_tcp.connect(host_charlist, port, opts, timeout)
  end
end
