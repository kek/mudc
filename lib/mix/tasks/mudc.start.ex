defmodule Mix.Tasks.Mudc.Start do
  @moduledoc """
  Starts the MUDC (Multi-User Dungeon Client) terminal interface.

  ## Usage

      mix mudc.start

  This will launch the Terminal UI that connects to MMapper at 172.24.0.1:4242.

  ## Controls

  - Type commands and press Enter to send them to the MUD
  - Use Up/Down arrows to navigate command history
  - Type 'quit' or 'exit' or press Ctrl+C to quit
  - Ctrl+D also quits the application

  ## Configuration

  The default connection is to MMapper at 172.24.0.1:4242 (WSL to Windows host).
  To connect to a different host/port, you can modify the configuration in
  lib/mudc/telnet/connection_config.ex before starting.
  """

  use Mix.Task

  @shortdoc "Starts the MUD client terminal interface"

  @impl Mix.Task
  def run(_args) do
    # Ensure the application and dependencies are started
    Mix.Task.run("app.start")

    # Start the TermUI runtime with the Terminal component
    IO.puts("\nStarting MUDC...")
    IO.puts("Press Ctrl+C to quit\n")

    case TermUI.Runtime.run(component: Mudc.UI.Terminal) do
      :ok ->
        IO.puts("\nGoodbye!")

      {:error, reason} ->
        IO.puts("\nError starting UI: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
