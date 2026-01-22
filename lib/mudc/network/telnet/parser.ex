defmodule Mudc.Network.Telnet.Parser do
  @moduledoc """
  Pure Telnet protocol parser using binary pattern matching.

  Parses raw TCP data into:
  - Plain text chunks
  - Telnet commands (WILL, WONT, DO, DONT)
  - Subnegotiations (SB ... SE)

  Handles:
  - IAC IAC (escaped 255 byte)
  - Partial data buffering
  - Incomplete subnegotiations

  ## Example

      {:ok, events, rest} = Parser.parse(<<255, 251, 201, "Hello">>)
      # events = [{:will, 201}, {:text, "Hello"}]
      # rest = <<>> (no leftover bytes)
  """

  alias Mudc.Network.Telnet.Constants, as: TC

  @type event ::
          {:text, binary()}
          | {:will, byte()}
          | {:wont, byte()}
          | {:do, byte()}
          | {:dont, byte()}
          | {:subneg, byte(), binary()}
          | {:ga}
          | {:nop}

  @type parse_result :: {:ok, [event()], binary()}

  @doc """
  Parse binary data into telnet events.

  Returns `{:ok, events, remaining}` where:
  - `events` is a list of parsed events
  - `remaining` is any incomplete data that needs more bytes
  """
  @spec parse(binary()) :: parse_result()
  def parse(data) when is_binary(data) do
    parse_loop(data, [], <<>>)
  end

  # Main parsing loop
  defp parse_loop(<<>>, events, text_acc) do
    events = flush_text(events, text_acc)
    {:ok, Enum.reverse(events), <<>>}
  end

  # IAC IAC - escaped 255 byte
  defp parse_loop(<<255, 255, rest::binary>>, events, text_acc) do
    parse_loop(rest, events, text_acc <> <<255>>)
  end

  # IAC WILL option
  defp parse_loop(<<255, 251, option, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:will, option} | events], <<>>)
  end

  # IAC WONT option
  defp parse_loop(<<255, 252, option, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:wont, option} | events], <<>>)
  end

  # IAC DO option
  defp parse_loop(<<255, 253, option, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:do, option} | events], <<>>)
  end

  # IAC DONT option
  defp parse_loop(<<255, 254, option, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:dont, option} | events], <<>>)
  end

  # IAC GA (Go Ahead)
  defp parse_loop(<<255, 249, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:ga} | events], <<>>)
  end

  # IAC NOP
  defp parse_loop(<<255, 241, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)
    parse_loop(rest, [{:nop} | events], <<>>)
  end

  # IAC SB option ... IAC SE (subnegotiation)
  defp parse_loop(<<255, 250, option, rest::binary>>, events, text_acc) do
    events = flush_text(events, text_acc)

    case extract_subnegotiation(rest, <<>>) do
      {:ok, subneg_data, remaining} ->
        parse_loop(remaining, [{:subneg, option, subneg_data} | events], <<>>)

      {:incomplete, _partial} ->
        # Return what we have and buffer the incomplete subneg
        {:ok, Enum.reverse(events), <<255, 250, option>> <> rest}
    end
  end

  # Incomplete IAC sequence (need more data)
  defp parse_loop(<<255>>, events, text_acc) do
    events = flush_text(events, text_acc)
    {:ok, Enum.reverse(events), <<255>>}
  end

  # Incomplete IAC command (need option byte)
  defp parse_loop(<<255, cmd>> = partial, events, text_acc)
       when cmd in [251, 252, 253, 254, 250] do
    events = flush_text(events, text_acc)
    {:ok, Enum.reverse(events), partial}
  end

  # Regular text byte
  defp parse_loop(<<byte, rest::binary>>, events, text_acc) do
    parse_loop(rest, events, text_acc <> <<byte>>)
  end

  # Extract subnegotiation content until IAC SE
  defp extract_subnegotiation(<<>>, acc) do
    {:incomplete, acc}
  end

  # Found IAC SE - end of subnegotiation
  defp extract_subnegotiation(<<255, 240, rest::binary>>, acc) do
    {:ok, acc, rest}
  end

  # IAC IAC inside subnegotiation (escaped 255)
  defp extract_subnegotiation(<<255, 255, rest::binary>>, acc) do
    extract_subnegotiation(rest, acc <> <<255>>)
  end

  # Lone IAC at end - incomplete
  defp extract_subnegotiation(<<255>>, acc) do
    {:incomplete, acc}
  end

  # Regular byte in subnegotiation
  defp extract_subnegotiation(<<byte, rest::binary>>, acc) do
    extract_subnegotiation(rest, acc <> <<byte>>)
  end

  # Flush accumulated text to events list
  defp flush_text(events, <<>>), do: events
  defp flush_text(events, text), do: [{:text, text} | events]

  @doc """
  Build a Telnet command sequence.
  """
  def build_command(command, option) do
    <<255, command, option>>
  end

  @doc """
  Build a WILL response.
  """
  def will(option), do: build_command(TC.will(), option)

  @doc """
  Build a WONT response.
  """
  def wont(option), do: build_command(TC.wont(), option)

  @doc """
  Build a DO response.
  """
  def do_(option), do: build_command(TC.do_(), option)

  @doc """
  Build a DONT response.
  """
  def dont(option), do: build_command(TC.dont(), option)

  @doc """
  Build a subnegotiation sequence.
  """
  def subnegotiation(option, data) when is_binary(data) do
    # Escape any 255 bytes in the data
    escaped_data = escape_iac(data)
    <<255, 250, option>> <> escaped_data <> <<255, 240>>
  end

  # Escape IAC (255) bytes by doubling them
  defp escape_iac(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.flat_map(fn
      255 -> [255, 255]
      byte -> [byte]
    end)
    |> :binary.list_to_bin()
  end
end
