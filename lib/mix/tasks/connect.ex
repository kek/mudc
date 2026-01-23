defmodule Mix.Tasks.Connect do
  @moduledoc """
  Connect to a running Mudc instance via remote REPL.

  This task connects to a running Mudc node using distributed Erlang,
  allowing you to inspect and debug the application without restarting it.

  ## Prerequisites

    * Mudc must be running with: `mix start`
    * Cookie is automatically loaded from ~/.config/mudc/.erlang.cookie
    * Both start and connect tasks use the same cookie file

  ## Security

  Connections are restricted to localhost only (via short names).
  The secure cookie is stored in ~/.config/mudc/.erlang.cookie.

  ## Usage

      mix connect              # Connect to default node (mudc@hostname)
      mix connect mynode       # Connect to custom node name
      mix connect mudc myhost  # Connect to node on specific host

  ## Remote REPL Commands

  Once connected, you have full access to the running application:

      # Check connection status
      Mudc.status()

      # Send commands
      Mudc.send("look")

      # Inspect state
      :sys.get_state(Mudc.Network.Connection)

      # View logs
      Mudc.UI.LogBuffer.get_logs()

      # Hot reload code
      recompile()

  ## Disconnecting

  Press Ctrl+C twice to disconnect (leaves Mudc running).

  """
  @shortdoc "Connect to a running Mudc instance via remote REPL"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    node_name = Enum.at(args, 0, "mudc")
    hostname = Enum.at(args, 1) || get_hostname()

    cookie =
      case Mudc.Config.CookieManager.get_cookie() do
        {:ok, c} ->
          c

        {:error, reason} ->
          Mix.shell().error("Failed to get cookie: #{inspect(reason)}")
          Mix.shell().error("Make sure Mudc has been started at least once with 'mix start'")
          Mix.raise("Cannot connect without valid cookie.")
      end

    Mix.shell().info("Connecting to remote Mudc REPL...")
    Mix.shell().info("Target node: #{node_name}@#{hostname}")
    Mix.shell().info("Cookie: [secure]")
    Mix.shell().info("")
    Mix.shell().info("Note: Press Ctrl+C twice to disconnect (leaves Mudc running)")
    Mix.shell().info("")

    # Generate unique debug node name with timestamp
    debug_node = "debug_#{:os.system_time(:second)}"

    # Connect to the remote node
    System.cmd(
      "iex",
      [
        "--sname",
        debug_node,
        "--cookie",
        cookie,
        "--remsh",
        "#{node_name}@#{hostname}"
      ],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    )
  end

  defp get_hostname do
    case System.cmd("hostname", ["-s"]) do
      {hostname, 0} -> String.trim(hostname)
      _ -> "localhost"
    end
  end
end
