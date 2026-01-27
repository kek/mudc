defmodule Mudc.Config.Manager do
  @moduledoc """
  Lua configuration manager with hot-reload support.

  Uses ETS for fast concurrent reads (10-100x faster than GenServer calls).
  Loads configuration from ~/.config/mudc/config.lua (or $MUDC_CONFIG_PATH) and watches for changes.
  Uses FileSystem for instant notifications when config file changes.
  Broadcasts config_changed events when the configuration is updated.

  ## Performance

  - Config reads use ETS with `read_concurrency: true` for lock-free reads
  - Only reload/1 requires a GenServer call
  - FileSystem provides instant change notifications (no polling delay)

  ## Configuration File Format

  Configuration is a Lua program that returns a table:

  ```lua
  return {
    connection = {
      host = "localhost",
      port = 4242,
      auto_connect = true
    },
    ui = {
      viewport_height = 20,
      max_lines = 1000
    },
    scripting = {
      script_dirs = {"~/.config/mudc/scripts"},
      auto_reload = true
    },
    logging = {
      level = "info"
    }
  }
  ```

  The configuration file is a full Lua program, so you can use variables,
  conditionals, and functions to build your config dynamically.
  """

  use GenServer
  require Logger

  alias Mudc.ErrorHandler
  alias Mudc.Events.Bus

  @default_config_path "~/.config/mudc/config.lua"
  # ETS table name for config storage
  @table_name :mudc_config

  defstruct [:config_path, :last_modified, :fs_pid]

  # Default configuration values
  @defaults %{
    connection: %{
      host: "localhost",
      # Default port 4242 is for MMapper compatibility (MUME proxy)
      # Standard Telnet is 23, but Mudc is designed for MMapper integration
      port: 4242,
      auto_connect: true,
      timeout_ms: 5000,
      auto_reconnect_delay_ms: 5000
    },
    protocol: %{
      terminal_type: "XTERM-256COLOR"
    },
    auto_login: %{
      name_prompt: "By what name do you wish to be known?",
      password_prompt: "Account password:"
    },
    ui: %{
      viewport_height: 20,
      max_lines: 1000,
      max_history_size: 100,
      min_viewport_height: 5,
      vitals: %{
        warning_threshold: 0.7,
        danger_threshold: 0.3
      }
    },
    scripting: %{
      script_dirs: ["~/.config/mudc/scripts"],
      auto_reload: true
    },
    logging: %{
      level: "info",
      directory: "~/.config/mudc/logs",
      game_log_file: "game.log",
      max_log_size: 10 * 1024 * 1024
    }
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the entire configuration.
  Fast ETS read, no GenServer call required.
  """
  def get do
    case :ets.lookup(@table_name, :config) do
      [{:config, config}] -> config
      [] -> @defaults
    end
  end

  @doc """
  Get a configuration section.
  Fast ETS read, no GenServer call required.
  """
  def get(section) when is_atom(section) do
    config = get()
    Map.get(config, section, %{})
  end

  @doc """
  Get a specific configuration value.
  Fast ETS read, no GenServer call required.
  """
  def get(section, key) when is_atom(section) and is_atom(key) do
    section_config = get(section)
    Map.get(section_config, key)
  end

  @doc """
  Get a specific configuration value with a default.
  Fast ETS read, no GenServer call required.
  """
  def get(section, key, default) when is_atom(section) and is_atom(key) do
    section_config = get(section)
    Map.get(section_config, key, default)
  end

  @doc """
  Reload the configuration from disk.
  """
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Get the path to the configuration file.
  """
  def config_path do
    GenServer.call(__MODULE__, :config_path)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config_path =
      Keyword.get(opts, :config_path) ||
        System.get_env("MUDC_CONFIG_PATH") ||
        @default_config_path

    config_path = Path.expand(config_path)

    # Create ETS table for fast concurrent reads
    :ets.new(@table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    # Store initial defaults in ETS
    :ets.insert(@table_name, {:config, @defaults})

    state = %__MODULE__{
      config_path: config_path,
      last_modified: nil,
      fs_pid: nil
    }

    # Load initial configuration
    state = load_config(state)

    # Start watching for changes with FileSystem
    state = start_watching(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    state = load_config(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:config_path, _from, state) do
    {:reply, state.config_path, state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, state) do
    # FileSystem notification - config file changed
    if Path.expand(path) == state.config_path and :modified in events do
      Logger.debug("FileSystem detected config change: #{inspect(events)}")
      state = check_for_changes(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, :stop}, state) do
    Logger.debug("FileSystem watcher stopped")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop FileSystem watcher if running
    # FileSystem workers are linked and will be automatically stopped
    # when the parent process terminates, so no explicit stop needed
    _ = state.fs_pid

    # Clean up ETS table
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    :ok
  end

  # Private Functions

  defp load_config(state) do
    case File.read(state.config_path) do
      {:ok, content} ->
        case execute_lua_config(content) do
          {:ok, parsed} ->
            config = merge_config(@defaults, atomize_keys(parsed))
            mtime = get_mtime(state.config_path)

            # Store config in ETS for fast reads
            :ets.insert(@table_name, {:config, config})

            Logger.info("Loaded configuration from #{state.config_path}")
            Bus.publish(:config, {:loaded, config})
            %{state | last_modified: mtime}

          {:error, reason} ->
            ErrorHandler.log_warning(
              "Failed to execute Lua config file",
              reason,
              context: %{path: state.config_path}
            )

            state
        end

      {:error, :enoent} ->
        # Config file doesn't exist, use defaults and create directory
        ensure_config_dir(state.config_path)
        Logger.debug("Config file not found, using defaults")
        state

      {:error, reason} ->
        ErrorHandler.log_warning(
          "Failed to read config file",
          reason,
          context: %{path: state.config_path}
        )

        state
    end
  end

  defp execute_lua_config(lua_code) do
    try do
      # Create a new Lua state
      lua = :luerl.init()

      # Execute the Lua code and get the decoded result
      # do_dec automatically decodes Lua values to Erlang/Elixir terms
      # Lua tables become lists of {key, value} tuples
      case :luerl.do_dec(lua_code, lua) do
        {:ok, [result], _lua_state} ->
          # Convert Lua table format (list of tuples) to Elixir maps
          elixir_value = lua_to_elixir(result)
          {:ok, elixir_value}

        {:ok, [], _lua_state} ->
          {:error, "Lua config did not return a value"}

        {:lua_error, reason, _lua_state} ->
          {:error, {:lua_error, reason}}

        {:error, errors, warnings} ->
          {:error, {:compile_error, errors, warnings}}
      end
    rescue
      e ->
        {:error, {:exception, Exception.message(e)}}
    end
  end

  # Convert Luerl decoded values to proper Elixir structures
  # Luerl's do_dec returns Lua tables as lists of {key, value} tuples
  defp lua_to_elixir(value) when is_list(value) do
    # Check if it's a Lua table (all elements are 2-tuples)
    if Enum.all?(value, &(is_tuple(&1) and tuple_size(&1) == 2)) do
      # It's a table - convert to map
      Map.new(value, fn {k, v} ->
        {lua_to_elixir(k), lua_to_elixir(v)}
      end)
    else
      # It's an array - convert elements
      Enum.map(value, &lua_to_elixir/1)
    end
  end

  defp lua_to_elixir(value) when is_binary(value), do: value
  defp lua_to_elixir(value) when is_number(value), do: value
  defp lua_to_elixir(value) when is_boolean(value), do: value
  defp lua_to_elixir(nil), do: nil
  defp lua_to_elixir(value), do: value

  defp check_for_changes(state) do
    mtime = get_mtime(state.config_path)

    if mtime != state.last_modified and mtime != nil do
      Logger.info("Configuration file changed, reloading")
      # Read from ETS
      old_config = get()
      state = load_config(state)
      # Read from ETS
      new_config = get()

      if new_config != old_config do
        Bus.publish(:config, {:changed, new_config, old_config})
      end

      state
    else
      state
    end
  end

  defp start_watching(state) do
    # Use FileSystem for instant file change notifications
    config_dir = Path.dirname(state.config_path)

    case FileSystem.start_link(dirs: [config_dir], name: :config_watcher) do
      {:ok, pid} ->
        FileSystem.subscribe(:config_watcher)
        Logger.debug("Started FileSystem watcher for #{config_dir}")
        %{state | fs_pid: pid}

      {:error, {:already_started, pid}} ->
        FileSystem.subscribe(:config_watcher)
        Logger.debug("FileSystem watcher already running")
        %{state | fs_pid: pid}

      {:error, reason} ->
        # Fallback: FileSystem not supported on this platform
        Logger.warning(
          "FileSystem watcher unavailable: #{inspect(reason)}, config changes won't be detected"
        )

        state
    end
  end

  defp get_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp ensure_config_dir(config_path) do
    dir = Path.dirname(config_path)

    unless File.dir?(dir) do
      File.mkdir_p!(dir)
    end
  end

  defp merge_config(defaults, parsed) do
    Map.merge(defaults, parsed, fn _key, default, parsed_val ->
      if is_map(default) and is_map(parsed_val) do
        Map.merge(default, parsed_val)
      else
        parsed_val
      end
    end)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      value = atomize_keys(v)
      {key, value}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end
