defmodule Mudc.UI.Screens.DebugScreen do
  @moduledoc """
  Debug log screen state and rendering logic.

  Displays ASCII dog art and scrollable debug logs with syntax highlighting.

  This module provides helper functions for the main UI.App component,
  not a standalone TermUI component.
  """

  use TermUI.Elm

  alias Mudc.UI.ScrollState
  alias TermUI.Renderer.Style

  # Stub implementations to satisfy TermUI.Elm behavior
  # These are never called - only helper functions are used
  def init(_), do: %{}
  def update(_, state), do: {state, []}
  def view(_), do: text("")

  @dog_art """
      / \\__
     (    @\\___
     /         O
    /   (_____/
   /_____/   U
  """

  @dog_art_padding 4
  @min_viewport_height 5

  defstruct log_lines: [],
            scroll: %ScrollState{}

  @type t :: %__MODULE__{
          log_lines: [String.t()],
          scroll: ScrollState.t()
        }

  @doc """
  Create a new debug screen.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Update log lines (typically from LogBuffer).
  """
  def update_logs(%__MODULE__{} = screen, log_lines, term_height, reserved_lines) do
    log_viewport_height = calculate_log_viewport_height(term_height, reserved_lines)
    scroll = ScrollState.maybe_auto_scroll(screen.scroll, length(log_lines), log_viewport_height)
    %{screen | log_lines: log_lines, scroll: scroll}
  end

  @doc """
  Handle scroll event.
  """
  def handle_scroll(%__MODULE__{} = screen, delta, term_height, reserved_lines) do
    log_viewport_height = calculate_log_viewport_height(term_height, reserved_lines)
    scroll = ScrollState.apply_scroll(screen.scroll, delta, length(screen.log_lines), log_viewport_height)
    %{screen | scroll: scroll}
  end

  @doc """
  Handle scroll to top.
  """
  def scroll_to_top(%__MODULE__{} = screen) do
    scroll = ScrollState.scroll_to_top(screen.scroll)
    %{screen | scroll: scroll}
  end

  @doc """
  Handle scroll to bottom.
  """
  def scroll_to_bottom(%__MODULE__{} = screen, term_height, reserved_lines) do
    log_viewport_height = calculate_log_viewport_height(term_height, reserved_lines)
    scroll = ScrollState.scroll_to_bottom(screen.scroll, length(screen.log_lines), log_viewport_height)
    %{screen | scroll: scroll}
  end

  @doc """
  Handle resize event - clamp scroll offset.
  """
  def handle_resize(%__MODULE__{} = screen, term_height, reserved_lines) do
    log_viewport_height = calculate_log_viewport_height(term_height, reserved_lines)
    scroll = ScrollState.clamp(screen.scroll, length(screen.log_lines), log_viewport_height)
    %{screen | scroll: scroll}
  end

  @doc """
  Render the debug screen with dog art and logs.
  """
  def render(screen, term_height, term_width, reserved_lines) do
    {dog_lines, log_viewport_height} = calculate_dimensions(term_height, reserved_lines)
    visible_logs = get_visible_logs(screen, log_viewport_height)
    scroll_info = build_scroll_info(screen, log_viewport_height)

    dog_elements = render_dog_art(dog_lines)
    log_elements = render_log_lines(visible_logs)
    log_header = build_log_header(term_width, scroll_info)

    border_width = min(term_width - 2, 78)
    border = text("+" <> String.duplicate("-", border_width) <> "+", Style.new(fg: :blue))

    stack(:vertical, [
      border,
      stack(:vertical, dog_elements),
      border,
      text(log_header, Style.new(fg: :cyan, attrs: [:bold])),
      border,
      stack(:vertical, log_elements),
      border
    ])
  end

  # Private helpers

  defp calculate_log_viewport_height(term_height, reserved_lines) do
    dog_lines_count = String.split(@dog_art, "\n", trim: true) |> length()
    dog_height = dog_lines_count + @dog_art_padding
    available_height = term_height - reserved_lines
    max(available_height - dog_height, @min_viewport_height)
  end

  defp calculate_dimensions(term_height, reserved_lines) do
    dog_lines = String.split(@dog_art, "\n", trim: true)
    log_viewport_height = calculate_log_viewport_height(term_height, reserved_lines)
    {dog_lines, log_viewport_height}
  end

  defp get_visible_logs(screen, log_viewport_height) do
    visible_logs =
      screen.log_lines
      |> Enum.drop(screen.scroll.scroll_offset)
      |> Enum.take(log_viewport_height)

    # Pad with empty lines if needed
    visible_logs ++ List.duplicate("", log_viewport_height - length(visible_logs))
  end

  defp build_scroll_info(screen, log_viewport_height) do
    total_logs = length(screen.log_lines)

    if total_logs > 0 do
      first = screen.scroll.scroll_offset + 1
      last = min(screen.scroll.scroll_offset + log_viewport_height, total_logs)
      "#{first}-#{last}/#{total_logs}"
    else
      "0/0"
    end
  end

  defp render_dog_art(dog_lines) do
    Enum.map(dog_lines, fn line ->
      text("  " <> line, Style.new(fg: :bright_yellow, attrs: [:bold]))
    end)
  end

  defp render_log_lines(visible_logs) do
    Enum.map(visible_logs, fn line ->
      style = log_line_style(line)
      text(line, style)
    end)
  end

  defp log_line_style(line) do
    cond do
      String.contains?(line, "[error]") -> Style.new(fg: :red, attrs: [:bold])
      String.contains?(line, "[warning]") -> Style.new(fg: :yellow)
      String.contains?(line, "[info]") -> Style.new(fg: :green)
      String.contains?(line, "[debug]") -> Style.new(fg: :cyan, attrs: [:dim])
      true -> Style.new(fg: :white)
    end
  end

  defp build_log_header(term_width, scroll_info) do
    border_width = min(term_width - 2, 78)
    scroll_info_len = String.length(scroll_info)
    label = "DEBUG LOGS "
    padding_size = max(border_width - scroll_info_len - String.length(label) - 3, 0)

    label <> String.duplicate(" ", padding_size) <> " " <> scroll_info
  end
end
