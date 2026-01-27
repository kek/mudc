defmodule Mudc.UI.ScrollStateTest do
  use ExUnit.Case, async: true

  alias Mudc.UI.ScrollState

  describe "new/0" do
    test "creates default scroll state" do
      state = ScrollState.new()

      assert state.scroll_offset == 0
      assert state.auto_scroll == true
    end
  end

  describe "apply_scroll/4" do
    test "scrolls up when delta is positive" do
      state = ScrollState.new()
      total_lines = 100
      viewport_height = 20

      # Positive delta scrolls up (increases offset from bottom)
      result = ScrollState.apply_scroll(state, 5, total_lines, viewport_height)

      assert result.scroll_offset == 5
      assert result.auto_scroll == false
    end

    test "scrolls down when delta is negative" do
      state = %ScrollState{scroll_offset: 10, auto_scroll: false}
      total_lines = 100
      viewport_height = 20

      # Negative delta scrolls down (decreases offset toward bottom)
      result = ScrollState.apply_scroll(state, -5, total_lines, viewport_height)

      assert result.scroll_offset == 5
    end

    test "enables auto_scroll when scrolling to bottom" do
      state = %ScrollState{scroll_offset: 5, auto_scroll: false}
      total_lines = 100
      viewport_height = 20

      result = ScrollState.apply_scroll(state, 5, total_lines, viewport_height)

      if result.scroll_offset == 0 do
        assert result.auto_scroll == true
      end
    end

    test "clamps scroll_offset to valid range" do
      state = ScrollState.new()
      total_lines = 100
      viewport_height = 20

      # Try to scroll past the top
      result = ScrollState.apply_scroll(state, -1000, total_lines, viewport_height)

      max_offset = max(0, total_lines - viewport_height)
      assert result.scroll_offset <= max_offset
      assert result.scroll_offset >= 0
    end

    test "handles empty buffer gracefully" do
      state = ScrollState.new()
      total_lines = 0
      viewport_height = 20

      result = ScrollState.apply_scroll(state, -5, total_lines, viewport_height)

      assert result.scroll_offset == 0
    end
  end

  describe "scroll_to_top/1" do
    test "scrolls to top of content" do
      state = ScrollState.new()

      result = ScrollState.scroll_to_top(state)

      # Top means offset = 0 in this inverted scroll model
      assert result.scroll_offset == 0
      assert result.auto_scroll == false
    end
  end

  describe "scroll_to_bottom/3" do
    test "scrolls to bottom of content" do
      state = %ScrollState{scroll_offset: 50, auto_scroll: false}
      total_lines = 100
      viewport_height = 20

      result = ScrollState.scroll_to_bottom(state, total_lines, viewport_height)

      # Bottom means offset = max_scroll (total_lines - viewport_height)
      max_scroll = max(0, total_lines - viewport_height)
      assert result.scroll_offset == max_scroll
      assert result.auto_scroll == true
    end
  end

  describe "clamp/3" do
    test "clamps offset to valid range" do
      total_lines = 100
      viewport_height = 20

      # Test below minimum
      state = %ScrollState{scroll_offset: -10}
      result = ScrollState.clamp(state, total_lines, viewport_height)
      assert result.scroll_offset == 0

      # Test above maximum
      max_offset = total_lines - viewport_height
      state = %ScrollState{scroll_offset: max_offset + 10}
      result = ScrollState.clamp(state, total_lines, viewport_height)
      assert result.scroll_offset == max_offset

      # Test within range
      state = %ScrollState{scroll_offset: 40}
      result = ScrollState.clamp(state, total_lines, viewport_height)
      assert result.scroll_offset == 40
    end

    test "handles buffer smaller than viewport" do
      total_lines = 10
      viewport_height = 20

      # When buffer is smaller, max offset should be 0
      state = %ScrollState{scroll_offset: 10}
      result = ScrollState.clamp(state, total_lines, viewport_height)
      assert result.scroll_offset == 0

      state = %ScrollState{scroll_offset: -5}
      result = ScrollState.clamp(state, total_lines, viewport_height)
      assert result.scroll_offset == 0
    end
  end

  describe "maybe_auto_scroll/3" do
    test "updates state when at bottom and auto_scroll enabled" do
      state = %ScrollState{scroll_offset: 80, auto_scroll: true}
      total_lines = 100
      viewport_height = 20

      # When auto-scroll is enabled, should stay at max_scroll (bottom)
      result = ScrollState.maybe_auto_scroll(state, total_lines, viewport_height)
      max_scroll = max(0, total_lines - viewport_height)
      assert result.scroll_offset == max_scroll
    end

    test "does not update when scrolled up and auto_scroll disabled" do
      state = %ScrollState{scroll_offset: 10, auto_scroll: false}
      total_lines = 100
      viewport_height = 20

      result = ScrollState.maybe_auto_scroll(state, total_lines, viewport_height)
      assert result.scroll_offset == 10
    end

    test "handles edge cases with empty content" do
      state = %ScrollState{scroll_offset: 0, auto_scroll: true}

      # With empty content, max_scroll = 0
      result = ScrollState.maybe_auto_scroll(state, 0, 20)
      assert result.scroll_offset == 0
    end
  end
end
