defmodule Mudc.UI.ScrollUtils do
  @moduledoc """
  Utility functions for managing scroll state in viewports.

  Provides consistent scrolling behavior across different screens
  (game view, debug logs, etc.) with auto-scroll detection.
  """

  @doc """
  Applies a scroll delta to the current offset.

  Returns `{new_offset, auto_scroll}` where:
  - `new_offset` is clamped between 0 and max_scroll
  - `auto_scroll` is true if at the bottom of the viewport

  ## Examples

      iex> ScrollUtils.apply_scroll(0, 10, 100, 20)
      {10, false}

      iex> ScrollUtils.apply_scroll(70, 20, 100, 20)
      {80, true}  # At bottom (80 + 20 = 100)
  """
  def apply_scroll(current_offset, delta, total_lines, viewport_height) do
    max_scroll = calculate_max_scroll(total_lines, viewport_height)
    new_offset = current_offset + delta
    new_offset = clamp(new_offset, 0, max_scroll)
    auto_scroll = new_offset >= max_scroll

    {new_offset, auto_scroll}
  end

  @doc """
  Scrolls to the top of the viewport.

  Returns `{0, false}` (at top, auto-scroll disabled).
  """
  def scroll_to_top do
    {0, false}
  end

  @doc """
  Scrolls to the bottom of the viewport.

  Returns `{max_scroll, true}` (at bottom, auto-scroll enabled).
  """
  def scroll_to_bottom(total_lines, viewport_height) do
    max_scroll = calculate_max_scroll(total_lines, viewport_height)
    {max_scroll, true}
  end

  @doc """
  Clamps a scroll offset to valid range.

  Ensures the offset stays between 0 and the maximum scroll position.

  ## Examples

      iex> ScrollUtils.clamp_scroll(50, 100, 20)
      50

      iex> ScrollUtils.clamp_scroll(100, 100, 20)
      80  # Max scroll is 100 - 20 = 80
  """
  def clamp_scroll(offset, total_lines, viewport_height) do
    max_scroll = calculate_max_scroll(total_lines, viewport_height)
    clamp(offset, 0, max_scroll)
  end

  @doc """
  Adjusts scroll offset when auto-scrolling to stay at bottom.

  If auto-scroll is enabled and new content is added, maintains
  position at the bottom by recalculating max_scroll.

  Returns updated offset.
  """
  def adjust_auto_scroll(auto_scroll, total_lines, viewport_height) do
    if auto_scroll do
      calculate_max_scroll(total_lines, viewport_height)
    else
      nil
    end
  end

  @doc """
  Calculates the maximum scroll offset.

  The max scroll is the point where the last line is visible.
  Returns at least 0 (can't scroll when content fits viewport).

  ## Examples

      iex> ScrollUtils.calculate_max_scroll(100, 20)
      80

      iex> ScrollUtils.calculate_max_scroll(10, 20)
      0  # Content fits in viewport
  """
  def calculate_max_scroll(total_lines, viewport_height) do
    max(0, total_lines - viewport_height)
  end

  # Private helper
  defp clamp(value, min_val, max_val) do
    max(min_val, min(max_val, value))
  end
end
