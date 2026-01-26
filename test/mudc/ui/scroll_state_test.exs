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
    test "scrolls up when delta is negative" do
      state = ScrollState.new()
      total_lines = 100
      viewport_height = 20

      result = ScrollState.apply_scroll(state, -5, total_lines, viewport_height)

      assert result.scroll_offset == 5
      assert result.auto_scroll == false
    end

    test "scrolls down when delta is positive" do
      state = %ScrollState{scroll_offset: 10, auto_scroll: false}
      total_lines = 100
      viewport_height = 20

      result = ScrollState.apply_scroll(state, 5, total_lines, viewport_height)

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

  describe "scroll_to_top/3" do
    test "scrolls to top of content" do
      state = ScrollState.new()
      total_lines = 100
      viewport_height = 20

      result = ScrollState.scroll_to_top(state, total_lines, viewport_height)

      max_offset = max(0, total_lines - viewport_height)
      assert result.scroll_offset == max_offset
      assert result.auto_scroll == false
    end
  end

  describe "scroll_to_bottom/1" do
    test "scrolls to bottom of content" do
      state = %ScrollState{scroll_offset: 50, auto_scroll: false}

      result = ScrollState.scroll_to_bottom(state)

      assert result.scroll_offset == 0
      assert result.auto_scroll == true
    end
  end

  describe "clamp/3" do
    test "clamps offset to valid range" do
      total_lines = 100
      viewport_height = 20

      # Test below minimum
      assert ScrollState.clamp(-10, total_lines, viewport_height) == 0

      # Test above maximum
      max_offset = total_lines - viewport_height
      assert ScrollState.clamp(max_offset + 10, total_lines, viewport_height) == max_offset

      # Test within range
      assert ScrollState.clamp(40, total_lines, viewport_height) == 40
    end

    test "handles buffer smaller than viewport" do
      total_lines = 10
      viewport_height = 20

      # When buffer is smaller, max offset should be 0
      assert ScrollState.clamp(10, total_lines, viewport_height) == 0
      assert ScrollState.clamp(-5, total_lines, viewport_height) == 0
    end
  end

  describe "maybe_auto_scroll/2" do
    test "returns true when at bottom (offset 0)" do
      assert ScrollState.maybe_auto_scroll(0, 100) == true
    end

    test "returns false when scrolled up" do
      assert ScrollState.maybe_auto_scroll(10, 100) == false
    end

    test "handles edge cases" do
      assert ScrollState.maybe_auto_scroll(0, 0) == true
      assert ScrollState.maybe_auto_scroll(-1, 100) == true
    end
  end
end
