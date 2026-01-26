defmodule Mudc.Protocol.Supervisor do
  @moduledoc """
  Supervisor for protocol stack components.

  Groups related protocol processing components under a :rest_for_one strategy.
  This ensures that if the protocol dispatcher crashes, all dependent components
  (GMCP handler, game state) are restarted to maintain consistent state.

  ## Supervision Strategy

  Uses :rest_for_one so that:
  - If Dispatcher crashes → GMCP.Handler and GameState restart
  - If GMCP.Handler crashes → only GameState restarts
  - If GameState crashes → only GameState restarts

  This prevents stale protocol state after crashes.

  ## Children (in order)

  1. Protocol.Dispatcher - Routes parsed Telnet data to handlers
  2. Network.GMCP.Handler - Processes GMCP messages
  3. State.GameState - Stores vitals, room info, etc.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Protocol dispatcher must be first (others depend on it)
      Mudc.Protocol.Dispatcher,

      # GMCP handler processes GMCP subnegotiations
      Mudc.Network.GMCP.Handler,

      # Game state stores parsed GMCP data (vitals, room, etc.)
      Mudc.State.GameState
    ]

    # :rest_for_one ensures consistent state after crashes
    # If dispatcher restarts, handler and state restart too
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
