defmodule Mudc.Prompt do
  @moduledoc """
  Detects MUME prompt patterns.

  MUME prompts have a specific format:
  - Status character at start: *, !, o, # (indoor, riding, outdoor, alert)
  - Optional stat codes: CW, A1, M1, P8, S3, etc.
  - Optional stat values: XP:26.8k, TP:0, HP:123, Mana:45, Move:67
  - Ends with >

  Examples:
  - *# CW A1 M1 P8 S3 XP:26.8k TP:0>
  - *>
  - o>
  - Account>
  """

  require Logger

  @doc """
  Check if text matches a MUME prompt pattern.

  Only checks the current line (after the most recent newline).
  """
  def is_prompt?(text) do
    # Get only the current line (after the most recent \n)
    current_line =
      case String.split(text, "\n") do
        [] -> ""
        lines -> List.last(lines)
      end

    # Strip ANSI codes for pattern matching
    clean_text = strip_ansi(current_line)

    Logger.debug("is_prompt? checking current line: #{inspect(current_line)}")
    Logger.debug("After ANSI strip: #{inspect(clean_text)}")

    result =
      cond do
        # Empty line - not a prompt
        String.trim(clean_text) == "" ->
          Logger.debug("Empty line - not a prompt")
          false

        # Match MUME prompts with stat codes: *# CW A1 M1 P8 S3 XP:26.8k TP:0>
        # Must have status char at start and stat codes (letter followed by digit, or stat names with colons)
        Regex.match?(~r/^[*!o#].*\b([A-Z]\d+|[A-Z]{2}|XP:|TP:|HP:|Mana:|Move:).*>$/, clean_text) ->
          Logger.debug("Matched MUME prompt with stat codes")
          true

        # Match simple MUME prompts: *>, o>, !>
        Regex.match?(~r/^[*!o]>$/, clean_text) ->
          Logger.debug("Matched simple MUME prompt")
          true

        # Match Account> or Character> menu prompts
        Regex.match?(~r/^[A-Z][a-z]+>\s*$/, clean_text) ->
          Logger.debug("Matched menu prompt")
          true

        # Match simple shell prompts
        Regex.match?(~r/^[>#$%]\s*$/, clean_text) ->
          Logger.debug("Matched shell prompt")
          true

        # Default: not a prompt
        true ->
          Logger.debug("No prompt pattern matched")
          false
      end

    Logger.debug("Final prompt detection result: #{result}")
    result
  end

  # Strip ANSI escape codes from text for pattern matching
  defp strip_ansi(text) do
    String.replace(text, ~r/\e\[[0-9;]*m/, "")
  end
end
