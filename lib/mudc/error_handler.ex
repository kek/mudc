defmodule Mudc.ErrorHandler do
  @moduledoc """
  Standardized error handling and logging for Mudc.

  Provides consistent patterns for:
  - Error logging with structured context
  - Error event publishing
  - Error recovery strategies
  """

  require Logger
  alias Mudc.Events.Bus

  @doc """
  Logs an error and publishes an error event to the bus.

  ## Options

  - `:topic` - Event bus topic to publish to (default: `:error`)
  - `:event` - Event data to publish (default: `{:error, reason}`)
  - `:log_level` - Log level to use (`:error`, `:warning`, `:info`) (default: `:error`)
  - `:context` - Additional context map for logging

  ## Examples

      ErrorHandler.handle_error(
        "Failed to connect",
        reason,
        topic: :connection,
        context: %{host: "localhost", port: 4242}
      )
  """
  def handle_error(message, reason, opts \\ []) do
    log_level = Keyword.get(opts, :log_level, :error)
    context = Keyword.get(opts, :context, %{})
    topic = Keyword.get(opts, :topic)
    event = Keyword.get(opts, :event, {:error, reason})

    # Build log message with context
    log_message = build_log_message(message, reason, context)

    # Log at appropriate level
    case log_level do
      :error -> Logger.error(log_message)
      :warning -> Logger.warning(log_message)
      :info -> Logger.info(log_message)
      _ -> Logger.error(log_message)
    end

    # Publish event if topic provided
    if topic do
      Bus.publish(topic, event)
    end

    :ok
  end

  @doc """
  Logs a warning for a recoverable error.

  Use this for errors where the system can continue operating.

  ## Examples

      ErrorHandler.log_warning("Failed to load script", reason, context: %{path: path})
  """
  def log_warning(message, reason, opts \\ []) do
    handle_error(message, reason, Keyword.merge(opts, log_level: :warning))
  end

  @doc """
  Logs an error for a critical failure.

  Use this for errors that prevent normal operation.

  ## Examples

      ErrorHandler.log_error("Connection failed", reason, topic: :connection)
  """
  def log_error(message, reason, opts \\ []) do
    handle_error(message, reason, Keyword.merge(opts, log_level: :error))
  end

  @doc """
  Logs and publishes a connection error.

  Standard pattern for connection-related errors.
  """
  def connection_error(message, reason, context \\ %{}) do
    handle_error(
      message,
      reason,
      log_level: :error,
      topic: :connection,
      context: context
    )
  end

  @doc """
  Logs a warning for auto-retry scenarios.

  Use for errors where the system will automatically retry.
  """
  def retry_warning(message, reason, retry_delay_ms, context \\ %{}) do
    context_with_retry = Map.put(context, :retry_in_ms, retry_delay_ms)

    handle_error(
      message,
      reason,
      log_level: :warning,
      context: context_with_retry
    )
  end

  # Private helpers

  defp build_log_message(message, reason, context) when context == %{} do
    "#{message}: #{format_reason(reason)}"
  end

  defp build_log_message(message, reason, context) do
    context_str = format_context(context)
    "#{message}: #{format_reason(reason)} #{context_str}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp format_context(context) when map_size(context) == 0, do: ""

  defp format_context(context) do
    fields =
      context
      |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
      |> Enum.join(" ")

    "(#{fields})"
  end
end
