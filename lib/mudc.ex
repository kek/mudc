defmodule Mudc do
  @moduledoc """
  Mudc - A MUD client for MUME.

  ## Quick Start

      # Start the UI (connects via MMapper at localhost:4242)
      Mudc.run()

      # Or connect manually in iex
      Mudc.connect()
      Mudc.send("look")

      # Toggle to IEx REPL with F9, then resume:
      Mudc.resume_ui()
  """

  alias Mudc.Network.Connection
  alias Mudc.UI.App

  @doc """
  Starts the terminal UI for the MUD client.
  """
  def run do
    App.run()
  end

  @doc """
  Connects to the MUD server (via MMapper).

  ## Options
    - host: hostname (default: "localhost")
    - port: port number (default: 4242)
  """
  def connect(host \\ ~c"localhost", port \\ 4242) do
    Connection.connect(host, port)
  end

  @doc """
  Disconnects from the MUD server.
  """
  def disconnect do
    Connection.disconnect()
  end

  @doc """
  Sends a command to the MUD server.
  """
  def send(command) do
    Connection.send_command(command)
  end

  @doc """
  Returns the current connection status.
  """
  def status do
    Connection.status()
  end

  @doc """
  Resume the UI after switching to IEx mode with F9.

  When you press F9 in the game window, you can drop to the IEx REPL.
  Call this function to return to the game window.
  """
  def resume_ui do
    App.resume_ui()
  end
end
