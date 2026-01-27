defmodule Mudc.Scripting.Engine do
  @moduledoc """
  Luerl VM management for Lua scripting.

  Manages ONLY the Lua virtual machine state. Triggers, aliases, and script
  loading are handled by separate processes for better isolation.

  If the VM crashes, triggers and aliases are preserved in their respective
  managers and will work again once the VM restarts.

  ## Architecture

  - Engine: VM state only
  - TriggerManager: Pattern matching and trigger storage
  - AliasManager: Command expansion and alias storage
  - ScriptLoader: File loading and reload logic
  """

  use GenServer
  require Logger

  alias Mudc.Scripting.Sandbox
  alias Mudc.Scripting.API

  defstruct [:lua_state]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute Lua code.
  """
  def eval(code) when is_binary(code) do
    GenServer.call(__MODULE__, {:eval, code})
  end

  @doc """
  Call a Lua function by reference.
  Used by TriggerManager and AliasManager to execute callbacks.
  """
  def call_function(callback, args) do
    GenServer.call(__MODULE__, {:call_function, callback, args})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize Lua VM with sandbox and API
    lua_state = :luerl.init()
    lua_state = Sandbox.apply(lua_state)
    lua_state = API.install(lua_state, self())

    state = %__MODULE__{lua_state: lua_state}

    {:ok, state}
  end

  @impl true
  def handle_call({:eval, code}, _from, state) do
    case safe_eval(code, state.lua_state) do
      {:ok, result, new_lua_state} ->
        {:reply, {:ok, result}, %{state | lua_state: new_lua_state}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:call_function, callback, args}, _from, state) do
    case do_call_function(callback, args, state.lua_state) do
      {:ok, result, new_lua_state} ->
        {:reply, {:ok, result}, %{state | lua_state: new_lua_state}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:register_trigger, pattern, callback}, state) do
    # Forward to TriggerManager
    Mudc.Scripting.TriggerManager.register(pattern, callback)
    {:noreply, state}
  end

  @impl true
  def handle_info({:register_alias, name, callback}, state) do
    # Forward to AliasManager
    Mudc.Scripting.AliasManager.register(name, callback)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cleanup Lua VM state on shutdown
    # Luerl doesn't require explicit cleanup, but we clear our references
    if state.lua_state do
      Logger.debug("Cleaning up Lua VM on terminate")
      # VM will be garbage collected
    end

    :ok
  end

  # Private functions

  defp safe_eval(code, lua_state) do
    try do
      case :luerl.do(code, lua_state) do
        {:ok, result, new_state} ->
          {:ok, result, new_state}

        {:error, reason, _new_state} ->
          {:error, reason}

        other ->
          {:error, "Unexpected Luerl return: #{inspect(other)}"}
      end
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp do_call_function(callback, args, lua_state) do
    try do
      {result, new_state} = :luerl.call_function(callback, args, lua_state)
      {:ok, result, new_state}
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end
end
