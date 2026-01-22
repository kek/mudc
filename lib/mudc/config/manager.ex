defmodule Mudc.Config.Manager do
  @moduledoc """
  TOML configuration manager with hot-reload support.

  Loads configuration from ~/.config/mudc/config.toml and watches for changes.
  Broadcasts config_changed events when the configuration is updated.

  ## Configuration File Format

  ```toml
  [connection]
  host = "localhost"
  port = 4242
  auto_connect = false

  [ui]
  viewport_height = 20
  max_lines = 1000

  [scripting]
  script_dirs = ["~/.config/mudc/scripts"]
  auto_reload = true

  [logging]
  level = "info"
  ```
  """

  use GenServer
  require Logger

  alias Mudc.Events.Bus

  @default_config_path "~/.config/mudc/config.toml"
  # Check for changes every 5 seconds
  @check_interval 5_000

  defstruct [:config_path, :config, :last_modified, :watch_timer]

  # Default configuration values
  @defaults %{
    connection: %{
      host: "localhost",
      port: 4242,
      auto_connect: false
    },
    ui: %{
      viewport_height: 20,
      max_lines: 1000
    },
    scripting: %{
      script_dirs: ["~/.config/mudc/scripts"],
      auto_reload: true
    },
    logging: %{
      level: "info"
    }
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the entire configuration.
  """
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @doc """
  Get a configuration section.
  """
  def get(section) when is_atom(section) do
    GenServer.call(__MODULE__, {:get, section})
  end

  @doc """
  Get a specific configuration value.
  """
  def get(section, key) when is_atom(section) and is_atom(key) do
    GenServer.call(__MODULE__, {:get, section, key})
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
    config_path = Keyword.get(opts, :config_path, @default_config_path) |> Path.expand()

    state = %__MODULE__{
      config_path: config_path,
      config: @defaults,
      last_modified: nil,
      watch_timer: nil
    }

    # Load initial configuration
    state = load_config(state)

    # Start watching for changes
    state = start_watching(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:get, section}, _from, state) do
    value = Map.get(state.config, section, %{})
    {:reply, value, state}
  end

  @impl true
  def handle_call({:get, section, key}, _from, state) do
    section_config = Map.get(state.config, section, %{})
    value = Map.get(section_config, key)
    {:reply, value, state}
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
  def handle_info(:check_config, state) do
    state = check_for_changes(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp load_config(state) do
    case File.read(state.config_path) do
      {:ok, content} ->
        case Toml.decode(content) do
          {:ok, parsed} ->
            config = merge_config(@defaults, atomize_keys(parsed))
            mtime = get_mtime(state.config_path)
            Logger.info("Loaded configuration from #{state.config_path}")
            Bus.publish(:config, {:loaded, config})
            %{state | config: config, last_modified: mtime}

          {:error, reason} ->
            Logger.warning("Failed to parse config file: #{inspect(reason)}")
            state
        end

      {:error, :enoent} ->
        # Config file doesn't exist, use defaults and create directory
        ensure_config_dir(state.config_path)
        Logger.debug("Config file not found, using defaults")
        state

      {:error, reason} ->
        Logger.warning("Failed to read config file: #{inspect(reason)}")
        state
    end
  end

  defp check_for_changes(state) do
    mtime = get_mtime(state.config_path)

    if mtime != state.last_modified and mtime != nil do
      Logger.info("Configuration file changed, reloading")
      old_config = state.config
      state = load_config(state)

      if state.config != old_config do
        Bus.publish(:config, {:changed, state.config, old_config})
      end

      state
    else
      state
    end
  end

  defp start_watching(state) do
    timer = Process.send_after(self(), :check_config, @check_interval)
    schedule_next_check()
    %{state | watch_timer: timer}
  end

  defp schedule_next_check do
    Process.send_after(self(), :check_config, @check_interval)
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
