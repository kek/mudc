defmodule Mudc.Scripting.TriggerManager do
  @moduledoc """
  Manages trigger pattern matching and callbacks.

  Stores triggers independently from the Lua VM, so trigger registrations
  survive VM crashes. When game text arrives, checks all triggers and
  executes matching callbacks via the Lua VM.

  ## Example Trigger

      mud.trigger("You are hit", function()
        mud.echo("Ouch!")
      end)
  """

  use GenServer
  require Logger

  alias Mudc.Events.Bus
  alias Mudc.Scripting.Engine
  alias Mudc.ErrorHandler

  defstruct triggers: []

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new trigger.
  Pattern is matched against incoming game text.
  Callback is a Lua function reference to execute when pattern matches.
  """
  def register(pattern, callback) do
    GenServer.cast(__MODULE__, {:register, pattern, callback})
  end

  @doc """
  Get all registered triggers.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Clear all triggers.
  """
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Subscribe to game text events
    Bus.subscribe(:game_text)

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.triggers, state}
  end

  @impl true
  def handle_cast({:register, pattern, callback}, state) do
    triggers = [{pattern, callback} | state.triggers]
    Logger.debug("Registered trigger: #{pattern}")
    {:noreply, %{state | triggers: triggers}}
  end

  @impl true
  def handle_cast(:clear, state) do
    {:noreply, %{state | triggers: []}}
  end

  @impl true
  def handle_info({:event, :game_text, {:text, text}}, state) do
    check_triggers(text, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :game_text, {:prompt, text}}, state) do
    # Also check triggers against prompts (e.g., "Account>" trigger)
    check_triggers(text, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :game_text, _other}, state) do
    {:noreply, state}
  end

  # Check all triggers against incoming text
  defp check_triggers(text, state) do
    Enum.each(state.triggers, fn {pattern, callback} ->
      if String.contains?(text, pattern) do
        # Execute trigger callback via Engine
        case Engine.call_function(callback, [text]) do
          {:ok, _result} ->
            :ok

          {:error, reason} ->
            ErrorHandler.log_warning("Trigger callback error", reason,
              context: %{pattern: pattern}
            )
        end
      end
    end)
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
