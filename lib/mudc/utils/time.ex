defmodule Mudc.Utils.Time do
  @moduledoc """
  Shared time formatting utilities.

  Provides consistent timestamp formatting across the application.
  """

  @doc """
  Format the current local time as HH:MM:SS.

  ## Examples

      iex> Mudc.Utils.Time.format_timestamp()
      "14:32:05"
  """
  def format_timestamp do
    {{_y, _m, _d}, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0B:~2..0B:~2..0B", [h, m, s]) |> to_string()
  end
end
