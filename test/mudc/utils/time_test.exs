defmodule Mudc.Utils.TimeTest do
  use ExUnit.Case, async: true

  alias Mudc.Utils.Time

  describe "format_timestamp/0" do
    test "returns time in HH:MM:SS format" do
      timestamp = Time.format_timestamp()

      # Should match HH:MM:SS pattern
      assert timestamp =~ ~r/^\d{2}:\d{2}:\d{2}$/
    end

    test "uses 24-hour format" do
      timestamp = Time.format_timestamp()

      # Parse the hours
      [hours_str | _] = String.split(timestamp, ":")
      hours = String.to_integer(hours_str)

      # Hours should be 0-23
      assert hours >= 0 and hours <= 23
    end

    test "pads single digits with zero" do
      timestamp = Time.format_timestamp()

      # All parts should be exactly 2 digits
      parts = String.split(timestamp, ":")
      assert length(parts) == 3

      Enum.each(parts, fn part ->
        assert String.length(part) == 2
        assert part =~ ~r/^\d{2}$/
      end)
    end

    test "returns string type" do
      timestamp = Time.format_timestamp()
      assert is_binary(timestamp)
    end
  end
end
