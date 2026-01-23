defmodule Mudc.UI.LogHandler do
  @moduledoc """
  Custom :logger handler that forwards log messages to the LogBuffer.

  This handler captures all log messages and stores them in a buffer
  that can be accessed programmatically for debugging purposes.
  """

  @doc """
  Adds this handler to the Erlang :logger.
  Should be called after LogBuffer is started.
  """
  def attach do
    :logger.add_handler(:mudc_log_handler, __MODULE__, %{})
  end

  @doc """
  Removes this handler from the Erlang :logger.
  """
  def detach do
    :logger.remove_handler(:mudc_log_handler)
  end

  # :logger handler callbacks

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    message = format_message(msg)
    metadata = format_metadata(meta)

    Mudc.UI.LogBuffer.add_log(level, message, metadata)
  end

  defp format_message({:string, msg}), do: to_string(msg)
  defp format_message({:report, report}), do: inspect(report)

  defp format_message({format, args}) when is_list(args) do
    :io_lib.format(format, args) |> to_string()
  rescue
    _ -> "#{inspect(format)} #{inspect(args)}"
  end

  defp format_message(msg), do: to_string(msg)

  defp format_metadata(meta) do
    module = Map.get(meta, :mfa, {nil, nil, nil}) |> elem(0)
    if module, do: [module: module], else: []
  end
end
