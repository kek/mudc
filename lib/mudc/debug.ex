defmodule Mudc.Debug do
  @moduledoc """
  Helper module for debugging Mudc via remote REPL.

  This module provides convenient functions for inspecting application state,
  logs, and processes without having to remember long module names or function calls.

  ## Quick Start

  Connect to a running Mudc instance:

      ./connect.sh

  Then use these helper functions:

      iex> Mudc.Debug.status()        # Overall status
      iex> Mudc.Debug.logs()          # Recent logs
      iex> Mudc.Debug.errors()        # Error logs only
      iex> Mudc.Debug.processes()     # List all processes
      iex> Mudc.Debug.memory()        # Memory usage
      iex> Mudc.Debug.state()         # Connection state

  ## Examples

      # Check if everything is running
      iex> Mudc.Debug.health_check()

      # Find a specific log message
      iex> Mudc.Debug.search_logs("connection")

      # See what's using the most memory
      iex> Mudc.Debug.top_memory(5)

  """

  alias Mudc.UI.LogBuffer
  alias Mudc.Network.Connection
  alias Mudc.State.GameState
  alias Mudc.Utils.Time

  @doc """
  Show overall application status.
  """
  def status do
    IO.puts("\n=== Mudc Status ===")
    IO.puts("Connection: #{inspect(connection_status())}")
    IO.puts("Vitals: #{inspect(GameState.vitals())}")
    IO.puts("Room: #{inspect(GameState.room())}")
    IO.puts("Processes: #{Process.list() |> length()}")
    IO.puts("Memory: #{memory_mb()} MB")
    IO.puts("Uptime: #{uptime()}")
    :ok
  end

  @doc """
  Run a health check on all major components.
  """
  def health_check do
    IO.puts("\n=== Health Check ===")

    checks = [
      {"Connection", Process.whereis(Connection)},
      {"LogBuffer", Process.whereis(LogBuffer)},
      {"GMCP Handler", Process.whereis(Mudc.Network.GMCP.Handler)},
      {"Game State", Process.whereis(GameState)},
      {"Event Bus", Process.whereis(Mudc.Events.Bus)},
      {"Scripting Engine", Process.whereis(Mudc.Scripting.Engine)},
      {"TermUI Runtime", Process.whereis(TermUI.Runtime)}
    ]

    Enum.each(checks, fn {name, pid} ->
      status = if is_pid(pid) and Process.alive?(pid), do: "✓", else: "✗"
      IO.puts("#{status} #{name}: #{inspect(pid)}")
    end)

    :ok
  end

  @doc """
  Get recent N log lines (default: 20).
  """
  def logs(count \\ 20) do
    LogBuffer.recent(count)
  end

  @doc """
  Get only error logs.
  """
  def errors do
    LogBuffer.errors()
  end

  @doc """
  Get only warning logs.
  """
  def warnings do
    LogBuffer.warnings()
  end

  @doc """
  Search logs for a pattern.
  """
  def search_logs(pattern) do
    LogBuffer.search(pattern)
  end

  @doc """
  Clear all logs from the buffer.
  """
  def clear_logs do
    LogBuffer.clear()
  end

  @doc """
  Get connection state.
  """
  def state do
    case Process.whereis(Connection) do
      nil -> :not_running
      pid -> :sys.get_state(pid)
    end
  end

  @doc """
  Get GMCP handler state.
  """
  def gmcp_state do
    case Process.whereis(Mudc.Network.GMCP.Handler) do
      nil -> :not_running
      pid -> :sys.get_state(pid)
    end
  end

  @doc """
  Get game state (vitals, room, etc.).
  """
  def game_state do
    %{
      vitals: GameState.vitals(),
      room: GameState.room()
    }
  end

  @doc """
  List all supervised processes.
  """
  def processes do
    Supervisor.which_children(Mudc.Supervisor)
  end

  @doc """
  Show memory usage in MB.
  """
  def memory do
    mem = :erlang.memory()

    IO.puts("\n=== Memory Usage ===")
    IO.puts("Total: #{bytes_to_mb(mem[:total])} MB")
    IO.puts("Processes: #{bytes_to_mb(mem[:processes])} MB")
    IO.puts("Binary: #{bytes_to_mb(mem[:binary])} MB")
    IO.puts("ETS: #{bytes_to_mb(mem[:ets])} MB")
    IO.puts("Atom: #{bytes_to_mb(mem[:atom])} MB")

    :ok
  end

  @doc """
  Get total memory in MB.
  """
  def memory_mb do
    :erlang.memory(:total) |> bytes_to_mb()
  end

  @doc """
  Show top N processes by memory usage.
  """
  def top_memory(count \\ 10) do
    processes =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, [:memory, :registered_name]) do
          nil ->
            nil

          info ->
            memory = Keyword.get(info, :memory, 0)
            name = Keyword.get(info, :registered_name, pid)
            {name, memory, pid}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {_, mem, _} -> mem end, :desc)
      |> Enum.take(count)

    IO.puts("\n=== Top #{count} Processes by Memory ===")

    Enum.each(processes, fn {name, mem, pid} ->
      IO.puts("#{inspect(name)} (#{inspect(pid)}): #{bytes_to_mb(mem)} MB")
    end)

    :ok
  end

  @doc """
  Show process mailbox sizes (useful for finding bottlenecks).
  """
  def mailbox_sizes do
    processes =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, [:message_queue_len, :registered_name]) do
          nil ->
            nil

          info ->
            queue_len = Keyword.get(info, :message_queue_len, 0)
            name = Keyword.get(info, :registered_name, pid)
            {name, queue_len, pid}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {_, len, _} -> len > 0 end)
      |> Enum.sort_by(fn {_, len, _} -> len end, :desc)

    IO.puts("\n=== Process Mailbox Sizes (non-zero) ===")

    case processes do
      [] ->
        IO.puts("All mailboxes empty ✓")

      procs ->
        Enum.each(procs, fn {name, len, pid} ->
          IO.puts("#{inspect(name)} (#{inspect(pid)}): #{len} messages")
        end)
    end

    :ok
  end

  @doc """
  Get connection status.
  """
  def connection_status do
    Mudc.status()
  end

  @doc """
  Send a command to the MUD.
  """
  def send(command) do
    Mudc.send(command)
  end

  @doc """
  Get system uptime.
  """
  def uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime_ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end

  @doc """
  Get all application configuration.
  """
  def config do
    Application.get_all_env(:mudc)
  end

  @doc """
  Monitor memory usage every N seconds (default: 5).
  Press Ctrl+C to stop.
  """
  def monitor_memory(interval_seconds \\ 5) do
    IO.puts("Monitoring memory every #{interval_seconds} seconds. Press Ctrl+C to stop.\n")
    monitor_memory_loop(interval_seconds * 1000)
  end

  defp monitor_memory_loop(interval_ms) do
    IO.puts("#{Time.format_timestamp()} - Memory: #{memory_mb()} MB, Processes: #{length(Process.list())}")
    Process.sleep(interval_ms)
    monitor_memory_loop(interval_ms)
  end

  @doc """
  Trace calls to a module. Press Ctrl+C to stop.

  ## Examples

      iex> Mudc.Debug.trace(Mudc.Network.Connection)
      # Now all calls to Connection module will be traced
  """
  def trace(module) do
    IO.puts("Tracing calls to #{inspect(module)}. Press Ctrl+C to stop.\n")
    :dbg.tracer()
    :dbg.p(:all, :c)
    :dbg.tpl(module, :_, [])
    IO.puts("Tracing started. Call Mudc.Debug.stop_trace() to stop.")
    :ok
  end

  @doc """
  Stop all tracing.
  """
  def stop_trace do
    :dbg.stop()
    IO.puts("Tracing stopped.")
    :ok
  end

  @doc """
  Restart a crashed process by name.

  ## Examples

      iex> Mudc.Debug.restart(Mudc.Network.Connection)
  """
  def restart(module) do
    Supervisor.terminate_child(Mudc.Supervisor, module)
    Supervisor.restart_child(Mudc.Supervisor, module)
  end

  @doc """
  Dump current state to a formatted output.
  """
  def dump do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("MUDC DEBUG DUMP")
    IO.puts(String.duplicate("=", 60))

    status()
    IO.puts("")
    health_check()
    IO.puts("")
    memory()
    IO.puts("")
    mailbox_sizes()
    IO.puts("")

    IO.puts("Recent Logs (last 10):")
    logs(10) |> Enum.each(&IO.puts/1)

    IO.puts("\n" <> String.duplicate("=", 60))
    :ok
  end

  ## Private Helpers

  defp bytes_to_mb(bytes) when is_integer(bytes) do
    Float.round(bytes / 1024 / 1024, 2)
  end
end
