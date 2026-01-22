defmodule Mudc.UI.AnsiParserTest do
  use ExUnit.Case, async: true

  alias Mudc.UI.AnsiParser
  alias TermUI.Renderer.Style

  describe "parse/1" do
    test "parses plain text without ANSI codes" do
      result = AnsiParser.parse("Hello, World!")
      assert result == [{"Hello, World!", nil}]
    end

    test "parses empty string" do
      result = AnsiParser.parse("")
      assert result == []
    end

    test "parses single foreground color" do
      result = AnsiParser.parse("\e[31mRed text\e[0m")
      assert [{text, style}] = result
      assert text == "Red text"
      assert style.fg == :red
    end

    test "parses bright foreground color" do
      result = AnsiParser.parse("\e[91mBright red\e[0m")
      assert [{text, style}] = result
      assert text == "Bright red"
      assert style.fg == :bright_red
    end

    test "parses background color" do
      result = AnsiParser.parse("\e[44mBlue background\e[0m")
      assert [{text, style}] = result
      assert text == "Blue background"
      assert style.bg == :blue
    end

    test "parses bold attribute" do
      result = AnsiParser.parse("\e[1mBold text\e[0m")
      assert [{text, style}] = result
      assert text == "Bold text"
      assert MapSet.member?(style.attrs, :bold)
    end

    test "parses combined color and attribute" do
      result = AnsiParser.parse("\e[1;31mBold red\e[0m")
      assert [{text, style}] = result
      assert text == "Bold red"
      assert style.fg == :red
      assert MapSet.member?(style.attrs, :bold)
    end

    test "parses multiple segments" do
      result = AnsiParser.parse("Normal \e[31mred\e[0m normal")
      assert [{"Normal ", nil}, {"red", style}, {" normal", nil}] = result
      assert style.fg == :red
    end

    test "handles reset code" do
      result = AnsiParser.parse("\e[31mred\e[0m plain")
      assert [{"red", style}, {" plain", nil}] = result
      assert style.fg == :red
    end

    test "parses underline attribute" do
      result = AnsiParser.parse("\e[4mUnderlined\e[0m")
      assert [{text, style}] = result
      assert text == "Underlined"
      assert MapSet.member?(style.attrs, :underline)
    end

    test "parses italic attribute" do
      result = AnsiParser.parse("\e[3mItalic\e[0m")
      assert [{text, style}] = result
      assert text == "Italic"
      assert MapSet.member?(style.attrs, :italic)
    end

    test "parses dim attribute" do
      result = AnsiParser.parse("\e[2mDim\e[0m")
      assert [{text, style}] = result
      assert text == "Dim"
      assert MapSet.member?(style.attrs, :dim)
    end

    test "parses reverse attribute" do
      result = AnsiParser.parse("\e[7mReversed\e[0m")
      assert [{text, style}] = result
      assert text == "Reversed"
      assert MapSet.member?(style.attrs, :reverse)
    end

    test "parses strikethrough attribute" do
      result = AnsiParser.parse("\e[9mStrikethrough\e[0m")
      assert [{text, style}] = result
      assert text == "Strikethrough"
      assert MapSet.member?(style.attrs, :strikethrough)
    end

    test "parses 256-color foreground" do
      result = AnsiParser.parse("\e[38;5;196mColor 196\e[0m")
      assert [{text, style}] = result
      assert text == "Color 196"
      assert style.fg == 196
    end

    test "parses 256-color background" do
      result = AnsiParser.parse("\e[48;5;21mBG color 21\e[0m")
      assert [{text, style}] = result
      assert text == "BG color 21"
      assert style.bg == 21
    end

    test "parses true color RGB foreground" do
      result = AnsiParser.parse("\e[38;2;255;128;64mRGB color\e[0m")
      assert [{text, style}] = result
      assert text == "RGB color"
      assert style.fg == {255, 128, 64}
    end

    test "parses true color RGB background" do
      result = AnsiParser.parse("\e[48;2;0;128;255mRGB bg\e[0m")
      assert [{text, style}] = result
      assert text == "RGB bg"
      assert style.bg == {0, 128, 255}
    end

    test "merges adjacent segments with same style" do
      # Two identical color codes in a row should merge
      result = AnsiParser.parse("\e[31mHello\e[31m World\e[0m")
      assert [{text, style}] = result
      assert text == "Hello World"
      assert style.fg == :red
    end

    test "handles text starting with ANSI code" do
      result = AnsiParser.parse("\e[32mGreen from start\e[0m")
      assert [{text, style}] = result
      assert text == "Green from start"
      assert style.fg == :green
    end

    test "handles empty ANSI code (reset)" do
      # Empty ANSI code acts as reset, but both parts have nil style
      # so they get merged into a single segment
      result = AnsiParser.parse("Before\e[mAfter")
      assert [{"BeforeAfter", nil}] = result
    end

    test "parses all standard foreground colors" do
      colors = [
        {30, :black},
        {31, :red},
        {32, :green},
        {33, :yellow},
        {34, :blue},
        {35, :magenta},
        {36, :cyan},
        {37, :white}
      ]

      for {code, expected_color} <- colors do
        result = AnsiParser.parse("\e[#{code}mtest\e[0m")
        assert [{_, style}] = result
        assert style.fg == expected_color, "Failed for code #{code}"
      end
    end

    test "parses all bright foreground colors" do
      colors = [
        {90, :bright_black},
        {91, :bright_red},
        {92, :bright_green},
        {93, :bright_yellow},
        {94, :bright_blue},
        {95, :bright_magenta},
        {96, :bright_cyan},
        {97, :bright_white}
      ]

      for {code, expected_color} <- colors do
        result = AnsiParser.parse("\e[#{code}mtest\e[0m")
        assert [{_, style}] = result
        assert style.fg == expected_color, "Failed for code #{code}"
      end
    end

    test "parses all standard background colors" do
      colors = [
        {40, :black},
        {41, :red},
        {42, :green},
        {43, :yellow},
        {44, :blue},
        {45, :magenta},
        {46, :cyan},
        {47, :white}
      ]

      for {code, expected_color} <- colors do
        result = AnsiParser.parse("\e[#{code}mtest\e[0m")
        assert [{_, style}] = result
        assert style.bg == expected_color, "Failed for code #{code}"
      end
    end
  end

  describe "to_render_nodes/1" do
    test "converts plain segment to text node" do
      segments = [{"Hello", nil}]
      nodes = AnsiParser.to_render_nodes(segments)
      assert [node] = nodes
      assert node.type == :text
      assert node.content == "Hello"
      assert node.style == nil
    end

    test "converts styled segment to styled text node" do
      style = Style.new() |> Style.fg(:red)
      segments = [{"Red", style}]
      nodes = AnsiParser.to_render_nodes(segments)
      assert [node] = nodes
      assert node.type == :text
      assert node.content == "Red"
      assert node.style.fg == :red
    end

    test "converts multiple segments" do
      style = Style.new() |> Style.fg(:blue)
      segments = [{"Plain", nil}, {"Blue", style}]
      nodes = AnsiParser.to_render_nodes(segments)
      assert length(nodes) == 2
    end
  end

  describe "parse_to_nodes/1" do
    test "parses and converts in one step" do
      nodes = AnsiParser.parse_to_nodes("\e[33mYellow\e[0m")
      assert [node] = nodes
      assert node.type == :text
      assert node.content == "Yellow"
      assert node.style.fg == :yellow
    end
  end
end
