defmodule Mudc.UI.Screens.InfoScreen do
  @moduledoc """
  Info/Cat screen state and rendering logic.

  Displays ASCII art (currently a cat).

  This module provides helper functions for the main UI.App component,
  not a standalone TermUI component.
  """

  use TermUI.Elm

  alias TermUI.Renderer.Style

  # Stub implementations to satisfy TermUI.Elm behavior
  # These are never called - only helper functions are used
  def init(_), do: %{}
  def update(_, state), do: {state, []}
  def view(_), do: text("")

  @cat_art """
   /\\_/\\
  ( o.o )
   > ^ <
  """

  defstruct []

  @type t :: %__MODULE__{}

  @doc """
  Create a new info screen.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Render the cat ASCII art.
  """
  def render(_screen) do
    art_lines = String.split(@cat_art, "\n", trim: true)

    line_elements =
      Enum.map(art_lines, fn line ->
        text(line, Style.new(fg: :bright_yellow, attrs: [:bold]))
      end)

    stack(:vertical, [
      text("+" <> String.duplicate("-", 40) <> "+", Style.new(fg: :blue)),
      text(""),
      stack(:vertical, line_elements),
      text(""),
      text("+" <> String.duplicate("-", 40) <> "+", Style.new(fg: :blue))
    ])
  end
end
