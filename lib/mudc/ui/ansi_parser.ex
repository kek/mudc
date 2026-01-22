defmodule Mudc.UI.AnsiParser do
  @moduledoc """
  Parses ANSI escape sequences from MUD server text and converts them
  to styled text segments for rendering in term_ui.

  This module handles SGR (Select Graphic Rendition) sequences which
  control text colors and attributes like bold, underline, etc.

  ## Usage

      segments = AnsiParser.parse("Hello \e[31mred\e[0m world")
      # Returns: [{"Hello ", nil}, {"red", %Style{fg: :red}}, {" world", nil}]

  The returned segments can be rendered using term_ui's `text/2` function
  with the appropriate styles.
  """

  alias TermUI.Renderer.Style

  # Note: TermUI.Renderer.Style accepts:
  # - Named colors: :red, :blue, :bright_green, etc.
  # - 256-color palette: integers 0-255
  # - True color RGB: {r, g, b} tuples

  @type segment :: {String.t(), Style.t() | nil}

  # CSI (Control Sequence Introducer) pattern: ESC [ ... m
  @csi_pattern ~r/\e\[([0-9;]*)m/

  @doc """
  Parses a string containing ANSI escape sequences and returns
  a list of {text, style} segments.

  ## Examples

      iex> AnsiParser.parse("plain text")
      [{"plain text", nil}]

      iex> AnsiParser.parse("\e[31mred text\e[0m")
      [{"red text", %Style{fg: :red}}]
  """
  @spec parse(String.t()) :: [segment()]
  def parse(input) when is_binary(input) do
    parse_segments(input, Style.new(), [])
    |> Enum.reverse()
    |> merge_empty_segments()
  end

  @doc """
  Renders parsed segments as a list of term_ui render nodes.

  Returns a list suitable for use with `stack(:horizontal, ...)`.
  """
  @spec to_render_nodes([segment()]) :: [term()]
  def to_render_nodes(segments) do
    alias TermUI.Component.RenderNode

    Enum.map(segments, fn
      {text, nil} -> RenderNode.text(text)
      {text, style} -> RenderNode.text(text, style)
    end)
  end

  @doc """
  Convenience function that parses and converts to render nodes in one step.
  """
  @spec parse_to_nodes(String.t()) :: [term()]
  def parse_to_nodes(input) do
    input
    |> parse()
    |> to_render_nodes()
  end

  # Private implementation

  defp parse_segments("", _current_style, acc), do: acc

  defp parse_segments(input, current_style, acc) do
    case Regex.run(@csi_pattern, input, return: :index) do
      nil ->
        # No more escape sequences, add remaining text
        if input != "" do
          segment = {input, style_or_nil(current_style)}
          [segment | acc]
        else
          acc
        end

      [{match_start, match_len}, {params_start, params_len}] ->
        # Extract text before the escape sequence
        before_text = binary_part(input, 0, match_start)

        # Add text segment if non-empty
        acc =
          if before_text != "" do
            segment = {before_text, style_or_nil(current_style)}
            [segment | acc]
          else
            acc
          end

        # Parse the SGR parameters
        params_str = binary_part(input, params_start, params_len)
        new_style = apply_sgr_params(params_str, current_style)

        # Continue parsing after the escape sequence
        rest_start = match_start + match_len
        rest = binary_part(input, rest_start, byte_size(input) - rest_start)
        parse_segments(rest, new_style, acc)
    end
  end

  # Returns nil for default/empty styles to avoid unnecessary styling
  defp style_or_nil(%Style{} = style) do
    fg_empty = style.fg in [nil, :default]
    bg_empty = style.bg in [nil, :default]
    attrs_empty = MapSet.size(style.attrs) == 0

    if fg_empty and bg_empty and attrs_empty do
      nil
    else
      style
    end
  end

  # Parse SGR parameter string (e.g., "1;31" for bold red)
  defp apply_sgr_params("", style), do: style

  defp apply_sgr_params(params_str, style) do
    params_str
    |> String.split(";")
    |> Enum.map(&parse_int/1)
    |> apply_sgr_codes(style)
  end

  defp parse_int(""), do: 0

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> 0
    end
  end

  # Apply a list of SGR codes to a style
  defp apply_sgr_codes([], style), do: style

  defp apply_sgr_codes([code | rest], style) do
    {new_style, remaining} = apply_sgr_code(code, rest, style)
    apply_sgr_codes(remaining, new_style)
  end

  # SGR code handlers

  # Reset all attributes
  defp apply_sgr_code(0, rest, _style) do
    {Style.new(), rest}
  end

  # Bold
  defp apply_sgr_code(1, rest, style) do
    {Style.bold(style), rest}
  end

  # Dim/faint
  defp apply_sgr_code(2, rest, style) do
    {Style.dim(style), rest}
  end

  # Italic
  defp apply_sgr_code(3, rest, style) do
    {Style.italic(style), rest}
  end

  # Underline
  defp apply_sgr_code(4, rest, style) do
    {Style.underline(style), rest}
  end

  # Blink
  defp apply_sgr_code(5, rest, style) do
    {Style.blink(style), rest}
  end

  # Rapid blink (treat as blink)
  defp apply_sgr_code(6, rest, style) do
    {Style.blink(style), rest}
  end

  # Reverse video
  defp apply_sgr_code(7, rest, style) do
    {Style.reverse(style), rest}
  end

  # Hidden/conceal
  defp apply_sgr_code(8, rest, style) do
    {Style.hidden(style), rest}
  end

  # Strikethrough
  defp apply_sgr_code(9, rest, style) do
    {Style.strikethrough(style), rest}
  end

  # Normal intensity (neither bold nor dim)
  defp apply_sgr_code(22, rest, style) do
    style = %{style | attrs: MapSet.delete(style.attrs, :bold)}
    style = %{style | attrs: MapSet.delete(style.attrs, :dim)}
    {style, rest}
  end

  # Not italic
  defp apply_sgr_code(23, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :italic)}, rest}
  end

  # Not underlined
  defp apply_sgr_code(24, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :underline)}, rest}
  end

  # Not blinking
  defp apply_sgr_code(25, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :blink)}, rest}
  end

  # Not reversed
  defp apply_sgr_code(27, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :reverse)}, rest}
  end

  # Reveal (not hidden)
  defp apply_sgr_code(28, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :hidden)}, rest}
  end

  # Not strikethrough
  defp apply_sgr_code(29, rest, style) do
    {%{style | attrs: MapSet.delete(style.attrs, :strikethrough)}, rest}
  end

  # Standard foreground colors (30-37)
  defp apply_sgr_code(30, rest, style), do: {Style.fg(style, :black), rest}
  defp apply_sgr_code(31, rest, style), do: {Style.fg(style, :red), rest}
  defp apply_sgr_code(32, rest, style), do: {Style.fg(style, :green), rest}
  defp apply_sgr_code(33, rest, style), do: {Style.fg(style, :yellow), rest}
  defp apply_sgr_code(34, rest, style), do: {Style.fg(style, :blue), rest}
  defp apply_sgr_code(35, rest, style), do: {Style.fg(style, :magenta), rest}
  defp apply_sgr_code(36, rest, style), do: {Style.fg(style, :cyan), rest}
  defp apply_sgr_code(37, rest, style), do: {Style.fg(style, :white), rest}

  # Extended foreground color (256-color or RGB)
  defp apply_sgr_code(38, rest, style) do
    apply_extended_color(:fg, rest, style)
  end

  # Default foreground color
  defp apply_sgr_code(39, rest, style) do
    {Style.fg(style, :default), rest}
  end

  # Standard background colors (40-47)
  defp apply_sgr_code(40, rest, style), do: {Style.bg(style, :black), rest}
  defp apply_sgr_code(41, rest, style), do: {Style.bg(style, :red), rest}
  defp apply_sgr_code(42, rest, style), do: {Style.bg(style, :green), rest}
  defp apply_sgr_code(43, rest, style), do: {Style.bg(style, :yellow), rest}
  defp apply_sgr_code(44, rest, style), do: {Style.bg(style, :blue), rest}
  defp apply_sgr_code(45, rest, style), do: {Style.bg(style, :magenta), rest}
  defp apply_sgr_code(46, rest, style), do: {Style.bg(style, :cyan), rest}
  defp apply_sgr_code(47, rest, style), do: {Style.bg(style, :white), rest}

  # Extended background color (256-color or RGB)
  defp apply_sgr_code(48, rest, style) do
    apply_extended_color(:bg, rest, style)
  end

  # Default background color
  defp apply_sgr_code(49, rest, style) do
    {Style.bg(style, :default), rest}
  end

  # Bright foreground colors (90-97)
  defp apply_sgr_code(90, rest, style), do: {Style.fg(style, :bright_black), rest}
  defp apply_sgr_code(91, rest, style), do: {Style.fg(style, :bright_red), rest}
  defp apply_sgr_code(92, rest, style), do: {Style.fg(style, :bright_green), rest}
  defp apply_sgr_code(93, rest, style), do: {Style.fg(style, :bright_yellow), rest}
  defp apply_sgr_code(94, rest, style), do: {Style.fg(style, :bright_blue), rest}
  defp apply_sgr_code(95, rest, style), do: {Style.fg(style, :bright_magenta), rest}
  defp apply_sgr_code(96, rest, style), do: {Style.fg(style, :bright_cyan), rest}
  defp apply_sgr_code(97, rest, style), do: {Style.fg(style, :bright_white), rest}

  # Bright background colors (100-107)
  defp apply_sgr_code(100, rest, style), do: {Style.bg(style, :bright_black), rest}
  defp apply_sgr_code(101, rest, style), do: {Style.bg(style, :bright_red), rest}
  defp apply_sgr_code(102, rest, style), do: {Style.bg(style, :bright_green), rest}
  defp apply_sgr_code(103, rest, style), do: {Style.bg(style, :bright_yellow), rest}
  defp apply_sgr_code(104, rest, style), do: {Style.bg(style, :bright_blue), rest}
  defp apply_sgr_code(105, rest, style), do: {Style.bg(style, :bright_magenta), rest}
  defp apply_sgr_code(106, rest, style), do: {Style.bg(style, :bright_cyan), rest}
  defp apply_sgr_code(107, rest, style), do: {Style.bg(style, :bright_white), rest}

  # Unknown code - ignore
  defp apply_sgr_code(_code, rest, style) do
    {style, rest}
  end

  # Handle extended color sequences (256-color and true color)
  # Format: 38;5;N (256-color) or 38;2;R;G;B (true color)
  defp apply_extended_color(type, [5, color_index | rest], style)
       when color_index >= 0 and color_index <= 255 do
    style =
      case type do
        :fg -> Style.fg(style, color_index)
        :bg -> Style.bg(style, color_index)
      end

    {style, rest}
  end

  defp apply_extended_color(type, [2, r, g, b | rest], style)
       when r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255 do
    style =
      case type do
        :fg -> Style.fg(style, {r, g, b})
        :bg -> Style.bg(style, {r, g, b})
      end

    {style, rest}
  end

  # Invalid extended color sequence - skip
  defp apply_extended_color(_type, rest, style) do
    {style, rest}
  end

  # Merge adjacent segments with same style and remove empty text segments
  defp merge_empty_segments(segments) do
    segments
    |> Enum.reject(fn {text, _style} -> text == "" end)
    |> merge_adjacent_segments([])
  end

  defp merge_adjacent_segments([], acc), do: Enum.reverse(acc)

  defp merge_adjacent_segments([{text1, style1}, {text2, style2} | rest], acc)
       when style1 == style2 do
    merge_adjacent_segments([{text1 <> text2, style1} | rest], acc)
  end

  defp merge_adjacent_segments([segment | rest], acc) do
    merge_adjacent_segments(rest, [segment | acc])
  end
end
