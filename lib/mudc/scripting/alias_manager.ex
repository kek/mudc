defmodule Mudc.Scripting.AliasManager do
  @moduledoc """
  Manages command aliases and expansion.

  Stores aliases independently from the Lua VM, so alias registrations
  survive VM crashes. When a command is typed, checks if it's an alias
  and executes the callback via the Lua VM.

  ## Example Alias

      mud.alias("heal", function()
        mud.send("cast 'cure light'")
      end)
  """

  use GenServer
  require Logger

  alias Mudc.Scripting.Engine
  alias Mudc.ErrorHandler

  defstruct aliases: %{}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new alias.
  Name is the command to match.
  Callback is a Lua function reference to execute when alias is typed.
  """
  def register(name, callback) do
    GenServer.cast(__MODULE__, {:register, name, callback})
  end

  @doc """
  Process a command for alias expansion.
  Returns `{:alias, name}` if matched, or `:passthrough`.
  """
  def process_command(command) do
    GenServer.call(__MODULE__, {:process_command, command})
  end

  @doc """
  Get all registered aliases.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Clear all aliases.
  """
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state.aliases), state}
  end

  @impl true
  def handle_call({:process_command, command}, _from, state) do
    # Check if first word is an alias
    [first | rest] = String.split(command, " ", parts: 2)

    case Map.get(state.aliases, first) do
      nil ->
        {:reply, :passthrough, state}

      callback ->
        # Execute alias callback with remaining args
        args = if rest == [], do: "", else: hd(rest)

        case Engine.call_function(callback, [args]) do
          {:ok, _result} ->
            {:reply, {:alias, first}, state}

          {:error, reason} ->
            ErrorHandler.log_warning("Alias callback error", reason, context: %{alias: first})
            {:reply, :passthrough, state}
        end
    end
  end

  @impl true
  def handle_cast({:register, name, callback}, state) do
    aliases = Map.put(state.aliases, name, callback)
    Logger.debug("Registered alias: #{name}")
    {:noreply, %{state | aliases: aliases}}
  end

  @impl true
  def handle_cast(:clear, state) do
    {:noreply, %{state | aliases: %{}}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
