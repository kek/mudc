defmodule Mudc.Scripting.ScriptLoader do
  @moduledoc """
  Manages loading Lua scripts from the script directory.

  Watches the script directory and loads .lua files on startup.
  Can reload scripts on demand.

  Scripts are executed in the Lua VM managed by Scripting.Engine.
  """

  use GenServer
  require Logger

  alias Mudc.Scripting.Engine
  alias Mudc.ErrorHandler

  defstruct [:script_dir]

  @default_script_dir "~/.config/mudc/scripts"

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Load a specific Lua script file.
  """
  def load_file(path, name \\ __MODULE__) do
    GenServer.call(name, {:load_file, path})
  end

  @doc """
  Reload all scripts from the script directory.
  """
  def reload(name \\ __MODULE__) do
    GenServer.call(name, :reload)
  end

  @doc """
  Get the script directory path.
  """
  def script_dir(name \\ __MODULE__) do
    GenServer.call(name, :script_dir)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    script_dir =
      Keyword.get(opts, :script_dir, @default_script_dir)
      |> Path.expand()

    state = %__MODULE__{script_dir: script_dir}

    # Load all scripts on startup
    load_all_scripts(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:load_file, path}, _from, state) do
    result = load_script_file(path)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    # Clear existing triggers and aliases
    Mudc.Scripting.TriggerManager.clear()
    Mudc.Scripting.AliasManager.clear()

    # Reload all scripts
    load_all_scripts(state)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:script_dir, _from, state) do
    {:reply, state.script_dir, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp load_all_scripts(state) do
    if File.dir?(state.script_dir) do
      state.script_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".lua"))
      |> Enum.sort()
      |> Enum.each(fn filename ->
        path = Path.join(state.script_dir, filename)
        load_script_file(path)
      end)
    else
      Logger.debug("Script directory does not exist: #{state.script_dir}")
    end
  end

  defp load_script_file(path) do
    case File.read(path) do
      {:ok, code} ->
        case Engine.eval(code) do
          {:ok, _result} ->
            Logger.info("Loaded script: #{Path.basename(path)}")
            :ok

          {:error, reason} ->
            ErrorHandler.log_error(
              "Failed to execute script",
              reason,
              context: %{path: path}
            )

            {:error, reason}
        end

      {:error, reason} ->
        ErrorHandler.log_error(
          "Failed to read script",
          reason,
          context: %{path: path}
        )

        {:error, reason}
    end
  end
end
