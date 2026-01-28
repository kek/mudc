defmodule Mudc.UI.Screens.GameScreen do
  @moduledoc """
  Game screen state and rendering logic.

  Displays the main game text viewport with ANSI color support,
  vitals bar, and scrolling functionality.

  This module provides helper functions for the main UI.App component,
  not a standalone TermUI component.
  """

  use TermUI.Elm

  alias Mudc.UI.ScrollState
  alias Mudc.UI.AnsiParser
  alias TermUI.Renderer.Style

  # Stub implementations to satisfy TermUI.Elm behavior
  # These are never called - only helper functions are used
  def init(_), do: %{}
  def update(_, state), do: {state, []}
  def view(_), do: text("")

  @max_lines 1000

  defstruct lines: [],
            scroll: %ScrollState{},
            vitals: %{},
            room: %{}

  @type t :: %__MODULE__{
          lines: [String.t()],
          scroll: ScrollState.t(),
          vitals: map(),
          room: map()
        }

  @doc """
  Create a new game screen with initial welcome message.
  """
  def new do
    %__MODULE__{
      lines: [
        "Welcome to Mudc - MUME Client",
        "Type /connect to connect, /disconnect to disconnect, /quit to exit",
        "Press F4 for debug logs | /recompile to reload code | F3/F4/F5 switch screens"
      ]
    }
  end

  @doc """
  Add a line of game text to the buffer.
  Maintains max line limit and updates scroll if auto-scroll is enabled.
  """
  def add_line(%__MODULE__{} = screen, line, viewport_height) do
    lines = (screen.lines ++ [line]) |> Enum.take(-@max_lines)

    scroll = ScrollState.maybe_auto_scroll(screen.scroll, length(lines), viewport_height)

    %{screen | lines: lines, scroll: scroll}
  end

  @doc """
  Update vitals data (HP, mana, moves, etc.).
  """
  def update_vitals(%__MODULE__{} = screen, vitals) do
    %{screen | vitals: vitals}
  end

  @doc """
  Update room information.
  """
  def update_room(%__MODULE__{} = screen, room) do
    %{screen | room: room}
  end

  @doc """
  Handle scroll event.
  """
  def handle_scroll(%__MODULE__{} = screen, delta, viewport_height) do
    scroll = ScrollState.apply_scroll(screen.scroll, delta, length(screen.lines), viewport_height)
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
  def scroll_to_bottom(%__MODULE__{} = screen, viewport_height) do
    scroll = ScrollState.scroll_to_bottom(screen.scroll, length(screen.lines), viewport_height)
    %{screen | scroll: scroll}
  end

  @doc """
  Handle resize event - clamp scroll offset.
  """
  def handle_resize(%__MODULE__{} = screen, viewport_height) do
    scroll = ScrollState.clamp(screen.scroll, length(screen.lines), viewport_height)
    %{screen | scroll: scroll}
  end

  @doc """
  Render the game screen viewport.
  """
  def render_viewport(screen, viewport_height, term_width) do
    visible_lines =
      screen.lines
      |> Enum.drop(screen.scroll.scroll_offset)
      |> Enum.take(viewport_height)

    # Pad with empty lines if needed
    visible_lines =
      visible_lines ++ List.duplicate("", viewport_height - length(visible_lines))

    line_elements = Enum.map(visible_lines, &render_ansi_line/1)

    # Build viewport with border
    total_lines = length(screen.lines)

    scroll_info =
      "#{screen.scroll.scroll_offset + 1}-#{min(screen.scroll.scroll_offset + viewport_height, total_lines)}/#{total_lines}"

    # Use terminal width for borders, minus 2 for the "| " prefix
    border_width = max(term_width - 2, 20)
    scroll_info_len = String.length(scroll_info)

    top_border =
      "+" <>
        String.duplicate("-", border_width - scroll_info_len - 3) <> " " <> scroll_info <> " +"

    bottom_border = "+" <> String.duplicate("-", border_width) <> "+"

    content =
      Enum.map(line_elements, fn elem ->
        stack(:horizontal, [elem])
      end)

    stack(:vertical, [
      text(top_border, Style.new(fg: :blue)),
      stack(:vertical, content),
      text(bottom_border, Style.new(fg: :blue))
    ])
  end

  @doc """
  Render vitals bar (HP, mana, moves).
  """
  def render_vitals(screen) do
    vitals = screen.vitals

    if map_size(vitals) > 0 do
      # MUME-specific vitals display
      hp = Map.get(vitals, "hp", Map.get(vitals, "hits", "?"))
      max_hp = Map.get(vitals, "maxhp", Map.get(vitals, "maxhits", "?"))
      mana = Map.get(vitals, "mana", "?")
      max_mana = Map.get(vitals, "maxmana", "?")
      moves = Map.get(vitals, "moves", Map.get(vitals, "mv", "?"))
      max_moves = Map.get(vitals, "maxmoves", Map.get(vitals, "maxmv", "?"))

      hp_style = vitals_color(hp, max_hp)
      mana_style = vitals_color(mana, max_mana)
      moves_style = vitals_color(moves, max_moves)

      stack(:horizontal, [
        text("HP:", Style.new(fg: :white)),
        text("#{hp}/#{max_hp}", hp_style),
        text("  Mana:", Style.new(fg: :white)),
        text("#{mana}/#{max_mana}", mana_style),
        text("  Moves:", Style.new(fg: :white)),
        text("#{moves}/#{max_moves}", moves_style)
      ])
    else
      text("")
    end
  end

  # Private helpers

  defp render_ansi_line(""), do: text("")

  defp render_ansi_line(line) do
    segments = AnsiParser.parse(line)

    case segments do
      [] ->
        text("")

      [{text_content, nil}] ->
        # Single unstyled segment - simple case
        text(text_content)

      [{text_content, style}] ->
        # Single styled segment
        text(text_content, style)

      _ ->
        # Multiple segments - render as horizontal stack
        nodes = AnsiParser.to_render_nodes(segments)
        stack(:horizontal, nodes)
    end
  end

  defp vitals_color(current, max) when is_integer(current) and is_integer(max) and max > 0 do
    ratio = current / max

    cond do
      ratio > 0.7 -> Style.new(fg: :green)
      ratio > 0.3 -> Style.new(fg: :yellow)
      true -> Style.new(fg: :red, attrs: [:bold])
    end
  end

  defp vitals_color(_current, _max) do
    Style.new(fg: :white)
  end
end
