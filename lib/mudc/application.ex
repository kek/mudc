defmodule Mudc.Application do
  @moduledoc """
  OTP Application for Mudc MUD client.

  Supervision tree:
  - Mudc.UI.LogBuffer (log message buffer for UI display)
  - Mudc.Events.Bus (Registry-based PubSub)
  - Mudc.Config.Manager (TOML configuration)
  - Mudc.Protocol.Supervisor (:rest_for_one supervisor for protocol stack)
    - Mudc.Protocol.Dispatcher (Telnet protocol routing)
    - Mudc.Network.GMCP.Handler (GMCP message processing)
    - Mudc.State.GameState (ETS-backed game state)
  - Mudc.Network.Connection (TCP socket management)
  - Mudc.Network.AutoLogin (auto-login handler)
  - Mudc.Scripting.Engine (Lua VM only)
  - Mudc.Scripting.TriggerManager (trigger pattern matching)
  - Mudc.Scripting.AliasManager (command alias expansion)
  - Mudc.Scripting.ScriptLoader (script file loading)
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

      # Protocol stack supervisor (:rest_for_one for consistent state)
      # Groups: Dispatcher -> GMCP.Handler -> GameState
      Mudc.Protocol.Supervisor,

      # Network connection
      Mudc.Network.Connection,

      # Auto-login handler (sends credentials from env vars when prompted)
      Mudc.Network.AutoLogin,

      # Lua scripting components (split for better isolation)
      # VM crashes don't lose triggers/aliases
      Mudc.Scripting.Engine,
      Mudc.Scripting.TriggerManager,
      Mudc.Scripting.AliasManager,
      Mudc.Scripting.ScriptLoader
    ]

    opts = [strategy: :one_for_one, name: Mudc.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Attach our custom log handler after LogBuffer is started
    Mudc.UI.LogHandler.attach()

    result
  end
end
