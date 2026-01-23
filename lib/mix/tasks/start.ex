defmodule Mix.Tasks.Start do
  @moduledoc """
  Start Mudc with remote REPL support.

  This task starts the Mudc MUD client with distributed Erlang enabled,
  allowing you to connect from a remote IEx session for debugging.

  ## Security

  Cookies are automatically generated and stored in ~/.config/mudc/.erlang.cookie
  with secure permissions (0600). The cookie is reused on subsequent runs.

  ## Usage

      mix start              # Start with default node name (mudc)
      mix start mynode       # Start with custom node name

  ## Remote Connection

  To connect remotely from another terminal:

      mix connect              # Connect to default node
      mix connect mynode       # Connect to custom node name

  """
  @shortdoc "Start Mudc with remote REPL support"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    node_name = Enum.at(args, 0, "mudc")

    # Get the cookie
    cookie =
      case Mudc.Config.CookieManager.get_cookie() do
        {:ok, c} ->
          String.to_atom(c)

        {:error, reason} ->
          Mix.shell().error("Failed to get cookie: #{inspect(reason)}")
          Mix.raise("Cannot start without valid cookie. Check ~/.config/mudc/ permissions.")
      end

    # Start distributed Erlang if not already running
    unless Node.alive?() do
      case :net_kernel.start([String.to_atom(node_name), :shortnames]) do
        {:ok, _pid} ->
          Node.set_cookie(cookie)
          Mix.shell().info("Started distributed node: #{node()}")

        {:error, {:already_started, _pid}} ->
          # Already started, just set the cookie
          Node.set_cookie(cookie)

        {:error, reason} ->
          Mix.shell().error("Failed to start distributed node: #{inspect(reason)}")
          Mix.shell().info("Starting Mudc without distributed Erlang...")
      end
    end

    Mix.shell().info("Starting Mudc MUD Client...")
    Mix.shell().info("Node: #{if Node.alive?(), do: node(), else: "not distributed"}")

    if Node.alive?() do
      Mix.shell().info("To connect remotely, run in another terminal:")
      Mix.shell().info("  mix connect")
    end

    Mix.shell().info("")

    # Run Mudc in the current VM
    Mudc.run()
  end
end
