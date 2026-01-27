defmodule Mudc.Logging.GameLogger do
  @moduledoc """
  Logs all game output and user input to a file in ~/.config/mudc/game.log

  Subscribes to :game_text and :user_input events and writes timestamped entries to the log file.
  User input is prefixed with ">" to distinguish it from game output.
  The log file rotates when it exceeds a certain size.
  """

  use GenServer
  require Logger

  alias Mudc.Events.Bus
  alias Mudc.Utils.Time

  @log_dir "~/.config/mudc"
  @log_file "game.log"
  # 10 MB
  @max_log_size 10 * 1024 * 1024

  defstruct [:file, :log_path, :bytes_written]

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
    # Ensure log directory exists
    log_dir = Path.expand(@log_dir)
    File.mkdir_p!(log_dir)

    # Open log file
    log_path = Path.join(log_dir, @log_file)
    {:ok, file} = File.open(log_path, [:append, :utf8])

    # Write session start marker
    timestamp = Time.format_timestamp()
    IO.write(file, "\n=== Session started at #{timestamp} ===\n")

    # Subscribe to game text and user input events
    Bus.subscribe(:game_text)
    Bus.subscribe(:user_input)

    state = %__MODULE__{
      file: file,
      log_path: log_path,
      bytes_written: 0
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

    case IO.write(state.file, log_line) do
      :ok ->
        bytes = byte_size(log_line)
        new_bytes_written = state.bytes_written + bytes

        # Check if we need to rotate
        new_state =
          if new_bytes_written > @max_log_size do
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

    case IO.write(state.file, log_line) do
      :ok ->
        bytes = byte_size(log_line)
        new_bytes_written = state.bytes_written + bytes

        # Check if we need to rotate
        new_state =
          if new_bytes_written > @max_log_size do
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
    # Write session end marker
    timestamp = Time.format_timestamp()
    IO.write(state.file, "=== Session ended at #{timestamp} ===\n\n")

    # Close the log file
    File.close(state.file)

    :ok
  end

  # Private Functions

  defp do_rotate(state) do
    # Close current file
    File.close(state.file)

    # Rename current log to timestamped backup
    timestamp = :calendar.local_time() |> format_timestamp_filename()
    backup_path = String.replace(state.log_path, ".log", ".#{timestamp}.log")
    File.rename(state.log_path, backup_path)

    Logger.info("Rotated game log: #{backup_path}")

    # Open new log file
    {:ok, file} = File.open(state.log_path, [:append, :utf8])

    # Write session start marker
    time = Time.format_timestamp()
    IO.write(file, "\n=== Session started at #{time} (rotated) ===\n")

    %{state | file: file, bytes_written: 0}
  end

  defp format_timestamp_filename({{y, m, d}, {h, min, s}}) do
    :io_lib.format("~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B", [y, m, d, h, min, s])
    |> to_string()
  end
end
