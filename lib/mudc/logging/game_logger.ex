defmodule Mudc.Logging.GameLogger do
  @moduledoc """
  Logs all game output and user input to a file.

  Subscribes to :game_text and :user_input events and writes timestamped entries to the log file.
  User input is prefixed with ">" to distinguish it from game output.
  The log file rotates when it exceeds a certain size.

  Log directory and filename are configurable via the config file:
  - logging.directory (default: ~/.config/mudc/logs)
  - logging.game_log_file (default: game.log)
  - logging.max_log_size (default: 10MB)
  """

  use GenServer
  require Logger

  alias Mudc.Config.Manager, as: Config
  alias Mudc.Events.Bus
  alias Mudc.Utils.Time

  defstruct [:file, :log_path, :bytes_written, :max_log_size]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current log file path.
  """
  def log_path do
    GenServer.call(__MODULE__, :log_path)
  end

  @doc """
  Rotate the log file (closes current, starts new).
  """
  def rotate do
    GenServer.call(__MODULE__, :rotate)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Get log configuration from config file
    log_dir = Config.get(:logging, :directory, "~/.config/mudc/logs") |> Path.expand()
    log_file = Config.get(:logging, :game_log_file, "game.log")
    max_log_size = Config.get(:logging, :max_log_size, 10 * 1024 * 1024)

    # Ensure log directory exists
    File.mkdir_p!(log_dir)

    # Open log file with UTF-8 encoding
    log_path = Path.join(log_dir, log_file)
    {:ok, file} = File.open(log_path, [:append, :utf8])

    # Write session start marker
    timestamp = Time.format_timestamp()
    safe_write(file, "\n=== Session started at #{timestamp} ===\n")

    # Subscribe to game text and user input events
    Bus.subscribe(:game_text)
    Bus.subscribe(:user_input)

    state = %__MODULE__{
      file: file,
      log_path: log_path,
      bytes_written: 0,
      max_log_size: max_log_size
    }

    Logger.info("Game logger started: #{log_path}")

    {:ok, state}
  end

  @impl true
  def handle_call(:log_path, _from, state) do
    {:reply, state.log_path, state}
  end

  @impl true
  def handle_call(:rotate, _from, state) do
    new_state = do_rotate(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:event, :game_text, {:text, text}}, state) do
    # Log the text with timestamp
    timestamp = Time.format_timestamp()
    log_line = "[#{timestamp}] #{text}"

    case safe_write(state.file, log_line) do
      {:ok, bytes} ->
        new_bytes_written = state.bytes_written + bytes

        # Check if we need to rotate
        new_state =
          if new_bytes_written > state.max_log_size do
            do_rotate(%{state | bytes_written: new_bytes_written})
          else
            %{state | bytes_written: new_bytes_written}
          end

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to write to game log: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:event, :game_text, {:plain_text, _text}}, state) do
    # Ignore plain_text events (we only log the ANSI version)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, :user_input, {:command, command}}, state) do
    # Log user input with timestamp
    timestamp = Time.format_timestamp()
    log_line = "[#{timestamp}] > #{String.trim(command)}\n"

    case safe_write(state.file, log_line) do
      {:ok, bytes} ->
        new_bytes_written = state.bytes_written + bytes

        # Check if we need to rotate
        new_state =
          if new_bytes_written > state.max_log_size do
            do_rotate(%{state | bytes_written: new_bytes_written})
          else
            %{state | bytes_written: new_bytes_written}
          end

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to write user input to game log: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Write session end marker if file is still valid
    if is_pid(state.file) and Process.alive?(state.file) do
      timestamp = Time.format_timestamp()
      safe_write(state.file, "=== Session ended at #{timestamp} ===\n\n")

      # Close the log file
      File.close(state.file)
    end

    :ok
  end

  # Private Functions

  # Safe write that catches exceptions from terminated file descriptors
  defp safe_write(file, data) do
    try do
      case IO.write(file, data) do
        :ok -> {:ok, byte_size(data)}
        {:error, _} = error -> error
      end
    catch
      :error, {:terminated, _} -> {:error, :terminated}
      :error, reason -> {:error, reason}
    end
  end

  defp do_rotate(state) do
    # Close current file
    File.close(state.file)

    # Rename current log to timestamped backup
    timestamp = :calendar.local_time() |> format_timestamp_filename()
    backup_path = String.replace(state.log_path, ".log", ".#{timestamp}.log")
    File.rename(state.log_path, backup_path)

    Logger.info("Rotated game log: #{backup_path}")

    # Open new log file with UTF-8 encoding
    {:ok, file} = File.open(state.log_path, [:append, :utf8])

    # Write session start marker
    time = Time.format_timestamp()
    safe_write(file, "\n=== Session started at #{time} (rotated) ===\n")

    %{state | file: file, bytes_written: 0}
  end

  defp format_timestamp_filename({{y, m, d}, {h, min, s}}) do
    :io_lib.format("~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B", [y, m, d, h, min, s])
    |> to_string()
  end
end
