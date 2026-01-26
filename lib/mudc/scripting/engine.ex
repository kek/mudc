defmodule Mudc.Scripting.Engine do
  @moduledoc """
  Luerl VM management for Lua scripting.

  Manages the Lua virtual machine, triggers, and aliases.
  Subscribes to game text events to match triggers.

  ## Example script

      -- Register a trigger for damage messages
      mud.trigger("You are hit", function()
        mud.echo("Ouch!")
      end)

      -- Register an alias
      mud.alias("heal", function()
        mud.send("cast 'cure light'")
      end)
  """

  use GenServer
  require Logger

  alias Mudc.ErrorHandler
  alias Mudc.Events.Bus
  alias Mudc.Scripting.Sandbox
  alias Mudc.Scripting.API

  defstruct [:lua_state, :triggers, :aliases, :script_dir]

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
  Load a Lua script file.
  """
  def load_file(path) do
    GenServer.call(__MODULE__, {:load_file, path})
  end

  @doc """
  Process a command for alias expansion.
  Returns `{:alias, expanded}` if it was an alias, or `:passthrough`.
  """
  def process_command(command) do
    GenServer.call(__MODULE__, {:process_command, command})
  end

  @doc """
  Process game text for trigger matching.
  """
  def process_text(text) do
    GenServer.cast(__MODULE__, {:process_text, text})
  end

  @doc """
  Reload all scripts from the script directory.
  """
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    script_dir = Keyword.get(opts, :script_dir, default_script_dir())

    # Subscribe to game text for trigger matching
    Bus.subscribe(:game_text)

    state = %__MODULE__{
      lua_state: nil,
      triggers: [],
      aliases: %{},
      script_dir: script_dir
    }

    # Initialize Lua VM
    state = init_lua(state)

    # Load scripts from directory
    state = load_scripts(state)

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
  def handle_call({:load_file, path}, _from, state) do
    case File.read(path) do
      {:ok, code} ->
        case safe_eval(code, state.lua_state) do
          {:ok, _result, new_lua_state} ->
            Logger.info("Loaded script: #{path}")
            {:reply, :ok, %{state | lua_state: new_lua_state}}

          {:error, reason} ->
            ErrorHandler.log_error(
              "Failed to load script",
              reason,
              context: %{path: path}
            )

            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
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

        case call_lua_function(callback, [args], state.lua_state) do
          {:ok, _result, new_lua_state} ->
            {:reply, :alias_handled, %{state | lua_state: new_lua_state}}

          {:error, reason} ->
            ErrorHandler.log_warning("Alias callback error", reason)
            {:reply, :passthrough, state}
        end
    end
  end

  @impl true
  def handle_call(:reload, _from, state) do
    state = init_lua(state)
    state = load_scripts(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:process_text, text}, state) do
    state = check_triggers(text, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :game_text, {:text, text}}, state) do
    state = check_triggers(text, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:register_trigger, pattern, callback}, state) do
    triggers = [{pattern, callback} | state.triggers]
    {:noreply, %{state | triggers: triggers}}
  end

  @impl true
  def handle_info({:register_alias, name, callback}, state) do
    aliases = Map.put(state.aliases, name, callback)
    {:noreply, %{state | aliases: aliases}}
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

  defp init_lua(state) do
    lua_state = :luerl.init()
    lua_state = Sandbox.apply(lua_state)
    lua_state = API.install(lua_state, self())
    %{state | lua_state: lua_state, triggers: [], aliases: %{}}
  end

  defp load_scripts(state) do
    if File.dir?(state.script_dir) do
      state.script_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".lua"))
      |> Enum.sort()
      |> Enum.reduce(state, fn filename, acc ->
        path = Path.join(state.script_dir, filename)

        case File.read(path) do
          {:ok, code} ->
            case safe_eval(code, acc.lua_state) do
              {:ok, _result, new_lua_state} ->
                Logger.info("Loaded script: #{filename}")
                %{acc | lua_state: new_lua_state}

              {:error, reason} ->
                ErrorHandler.log_warning("Failed to load script", reason, context: %{file: filename})
                acc
            end

          {:error, reason} ->
            ErrorHandler.log_warning("Failed to read script", reason, context: %{file: filename})
            acc
        end
      end)
    else
      Logger.debug("Script directory does not exist: #{state.script_dir}")
      state
    end
  end

  defp safe_eval(code, lua_state) do
    try do
      {result, new_state} = :luerl.do(code, lua_state)
      {:ok, result, new_state}
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp call_lua_function(callback, args, lua_state) do
    try do
      {result, new_state} = :luerl.call_function(callback, args, lua_state)
      {:ok, result, new_state}
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp check_triggers(text, state) do
    Enum.reduce(state.triggers, state, fn {pattern, callback}, acc ->
      if String.contains?(text, pattern) do
        case call_lua_function(callback, [text], acc.lua_state) do
          {:ok, _result, new_lua_state} ->
            %{acc | lua_state: new_lua_state}

          {:error, reason} ->
            ErrorHandler.log_warning("Trigger callback error", reason)
            acc
        end
      else
        acc
      end
    end)
  end

  defp default_script_dir do
    Path.expand("~/.config/mudc/scripts")
  end
end
