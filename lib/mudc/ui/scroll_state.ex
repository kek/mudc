defmodule Mudc.UI.ScrollState do
  @moduledoc """
  Scroll state management for scrollable viewports.

  Tracks scroll offset and auto-scroll behavior for a viewport.
  Provides helpers for scroll operations and state updates.
  """

  alias Mudc.UI.ScrollUtils

  defstruct scroll_offset: 0,
            auto_scroll: true

  @type t :: %__MODULE__{
          scroll_offset: non_neg_integer(),
          auto_scroll: boolean()
        }

  @doc """
  Create a new scroll state with default values.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Apply a scroll delta to the state.
  Returns updated state with new offset and auto_scroll status.
  """
  def apply_scroll(%__MODULE__{} = state, delta, total_lines, viewport_height) do
    {new_offset, auto_scroll} =
      ScrollUtils.apply_scroll(
        state.scroll_offset,
        delta,
        total_lines,
        viewport_height
      )

    %{state | scroll_offset: new_offset, auto_scroll: auto_scroll}
  end

  @doc """
  Scroll to the top of the content.
  """
  def scroll_to_top(%__MODULE__{} = state) do
    {offset, auto_scroll} = ScrollUtils.scroll_to_top()
    %{state | scroll_offset: offset, auto_scroll: auto_scroll}
  end

  @doc """
  Scroll to the bottom of the content.
  """
  def scroll_to_bottom(%__MODULE__{} = state, total_lines, viewport_height) do
    {offset, auto_scroll} = ScrollUtils.scroll_to_bottom(total_lines, viewport_height)
    %{state | scroll_offset: offset, auto_scroll: auto_scroll}
  end

  @doc """
  Clamp scroll offset to valid range after resize or content change.
  """
  def clamp(%__MODULE__{} = state, total_lines, viewport_height) do
    offset = ScrollUtils.clamp_scroll(state.scroll_offset, total_lines, viewport_height)
    %{state | scroll_offset: offset}
  end

  @doc """
  Update scroll offset if auto-scroll is enabled.
  Call this when content is added to maintain scroll position at bottom.
  """
  def maybe_auto_scroll(%__MODULE__{auto_scroll: false} = state, _total_lines, _viewport_height) do
    state
  end

  def maybe_auto_scroll(%__MODULE__{auto_scroll: true} = state, total_lines, viewport_height) do
    offset = ScrollUtils.calculate_max_scroll(total_lines, viewport_height)
    %{state | scroll_offset: offset}
  end
end
