defmodule Mudc.Application do
  @moduledoc """
  OTP Application for Mudc MUD client.

  Supervision tree:
  - Mudc.UI.LogBuffer (log message buffer for UI display)
  - Mudc.Events.Bus (Registry-based PubSub)
  - Mudc.Config.Manager (TOML configuration)
  - Mudc.State.GameState (ETS-backed game state)
  - Mudc.Network.GMCP.Handler (GMCP message processing)
  - Mudc.Protocol.Dispatcher (Telnet protocol routing)
  - Mudc.Network.Connection (TCP socket management)
  - Mudc.Scripting.Engine (Lua scripting VM)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Log buffer must start first (logger handler needs it)
      Mudc.UI.LogBuffer,

      # Event bus must start early (other components publish to it)
      Mudc.Events.Bus,

      # Configuration manager (loads before other components)
      Mudc.Config.Manager,

      # Game state (ETS table for vitals, room info, etc.)
      Mudc.State.GameState,

      # GMCP handler
      Mudc.Network.GMCP.Handler,

      # Protocol dispatcher (routes parsed Telnet to handlers)
      Mudc.Protocol.Dispatcher,

      # Network connection
      Mudc.Network.Connection,

      # Auto-login handler (sends credentials from env vars when prompted)
      Mudc.Network.AutoLogin,

      # Lua scripting engine
      Mudc.Scripting.Engine
    ]

    opts = [strategy: :one_for_one, name: Mudc.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Attach our custom log handler after LogBuffer is started
    Mudc.UI.LogHandler.attach()

    result
  end
end
