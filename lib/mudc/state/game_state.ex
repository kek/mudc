defmodule Mudc.State.GameState do
  @moduledoc """
  ETS-backed game state storage.

  Provides fast concurrent reads without GenServer bottleneck.
  Subscribes to GMCP events and updates state automatically.

  ## State Keys

  - `:vitals` - Character vitals (HP, Mana, Moves, etc.)
  - `:room` - Current room information
  - `:status` - Character status (level, class, etc.)
  - `:affects` - Active effects/buffs

  ## Example

      # Get current vitals
      vitals = GameState.get(:vitals)
      # => %{"hp" => 100, "maxhp" => 100, ...}

      # Get specific value
      hp = GameState.get(:vitals, "hp")
      # => 100
  """

  use GenServer
  require Logger

  alias Mudc.Events.Bus

  @table __MODULE__

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get state for a key.
  """
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Get a nested value from state.
  """
  def get(key, subkey) do
    case get(key) do
      nil -> nil
      map when is_map(map) -> Map.get(map, subkey)
      _ -> nil
    end
  end

  @doc """
  Get all state as a map.
  """
  def all do
    @table
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc """
  Get vitals (convenience function).
  """
  def vitals, do: get(:vitals) || %{}

  @doc """
  Get room info (convenience function).
  """
  def room, do: get(:room) || %{}

  @doc """
  Get character status (convenience function).
  """
  def status, do: get(:status) || %{}

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast reads
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Subscribe to GMCP events
    Bus.subscribe(:gmcp_vitals)
    Bus.subscribe(:gmcp_room)
    Bus.subscribe(:gmcp_status)

    {:ok, %{}}
  end

  @impl true
  def handle_info({:event, :gmcp_vitals, data}, state) when is_map(data) do
    # Merge with existing vitals
    current = get(:vitals) || %{}
    updated = Map.merge(current, data)
    :ets.insert(@table, {:vitals, updated})
    Bus.publish(:state_changed, {:vitals, updated})
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :gmcp_room, data}, state) when is_map(data) do
    :ets.insert(@table, {:room, data})
    Bus.publish(:state_changed, {:room, data})
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :gmcp_status, data}, state) when is_map(data) do
    # Merge with existing status
    current = get(:status) || %{}
    updated = Map.merge(current, data)
    :ets.insert(@table, {:status, updated})
    Bus.publish(:state_changed, {:status, updated})
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
