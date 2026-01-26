defmodule Mudc.Network.Connection do
  @moduledoc """
  Facade for connection management.

  Delegates to Connection.Manager for backward compatibility with existing code.
  The actual implementation is split into:
  - Connection.Manager (lifecycle, auto-connect, reconnection)
  - Connection.Socket (TCP I/O)

  This separation improves crash recovery: socket crashes don't lose connection
  state (host/port), and the Manager can spawn a new Socket with the same params.
  """

  alias Mudc.Network.Connection.Manager

  @doc """
  Starts the connection manager.
  """
  def start_link(opts \\ []) do
    Manager.start_link(opts)
  end

  @doc """
  Connects to the MUD server.
  Uses configured defaults if not specified.
  """
  def connect(host \\ nil, port \\ nil) do
    Manager.connect(host, port)
  end

  @doc """
  Disconnects from the MUD server.
  """
  def disconnect do
    Manager.disconnect()
  end

  @doc """
  Sends a command to the MUD server.
  """
  def send_command(command) do
    Manager.send_command(command)
  end

  @doc """
  Returns the current connection status.
  """
  def status do
    Manager.status()
  end
end
