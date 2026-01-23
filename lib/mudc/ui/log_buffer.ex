defmodule Mudc.UI.LogBuffer do
  @moduledoc """
  GenServer that stores log messages in a circular buffer.

  Logs can be accessed programmatically via remote REPL for debugging:

      # In remote shell
      iex> Mudc.UI.LogBuffer.get_logs()
      ["10:23:45 [info] Connected to localhost:4242", ...]

      # Get recent logs
      iex> Mudc.UI.LogBuffer.get_logs() |> Enum.take(20)

      # Filter by level
      iex> Mudc.UI.LogBuffer.get_logs() |> Enum.filter(&String.contains?(&1, "[error]"))

      # Clear logs
      iex> Mudc.UI.LogBuffer.clear()

  See `docs/remote-repl.md` for more examples.
  """

  use GenServer

  @max_lines 500

  defstruct lines: [], subscribers: []

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a log line to the buffer.
  """
  def add_log(level, message, metadata \\ []) do
    GenServer.cast(__MODULE__, {:add_log, level, message, metadata})
  end

  @doc """
  Get all log lines.
  """
  def get_logs do
    GenServer.call(__MODULE__, :get_logs)
  end

  @doc """
  Clear all logs.
  """
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc """
  Get recent N log lines (default: 20).
  """
  def recent(count \\ 20) do
    get_logs() |> Enum.take(count)
  end

  @doc """
  Get logs filtered by level (:debug, :info, :warning, :error).
  """
  def filter_by_level(level) do
    level_str = "[#{level}]"
    get_logs() |> Enum.filter(&String.contains?(&1, level_str))
  end

  @doc """
  Get only error logs.
  """
  def errors do
    filter_by_level(:error)
  end

  @doc """
  Get only warning logs.
  """
  def warnings do
    filter_by_level(:warning)
  end

  @doc """
  Search logs for a pattern (case-insensitive).
  """
  def search(pattern) do
    pattern_lower = String.downcase(pattern)
    get_logs() |> Enum.filter(&String.contains?(String.downcase(&1), pattern_lower))
  end

  @doc """
  Subscribe to log updates. Subscriber receives {:log_update, lines} messages.
  """
  def subscribe do
    GenServer.cast(__MODULE__, {:subscribe, self()})
  end

  @doc """
  Unsubscribe from log updates.
  """
  def unsubscribe do
    GenServer.cast(__MODULE__, {:unsubscribe, self()})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:add_log, level, message, metadata}, state) do
    timestamp = format_timestamp()
    module = Keyword.get(metadata, :module, "")
    module_str = if module != "", do: " [#{inspect(module)}]", else: ""

    line = "#{timestamp} [#{level}]#{module_str} #{message}"

    lines = [line | state.lines] |> Enum.take(@max_lines)

    # Notify subscribers
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:log_update, lines})
    end)

    {:noreply, %{state | lines: lines}}
  end

  @impl true
  def handle_cast(:clear, state) do
    {:noreply, %{state | lines: []}}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    subscribers = [pid | state.subscribers] |> Enum.uniq()
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_call(:get_logs, _from, state) do
    {:reply, Enum.reverse(state.lines), state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: subscribers}}
  end

  defp format_timestamp do
    {{_y, _m, _d}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end
end
