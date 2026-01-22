defmodule Mudc.Telnet.Protocol do
  @moduledoc """
  Telnet protocol handling for IAC (Interpret As Command) sequences.

  Handles encoding and decoding of Telnet protocol commands and negotiations.
  """

  # Telnet protocol constants (RFC 854)
  @iac 255         # Interpret As Command
  @telnet_dont 254 # Don't perform option
  @telnet_do 253   # Do perform option
  @telnet_wont 252 # Won't perform option
  @telnet_will 251 # Will perform option
  @telnet_sb 250   # Subnegotiation begin
  @telnet_se 240   # Subnegotiation end

  @type decoded :: %{text: binary(), commands: [command()]}
  @type command :: {:will | :wont | :do | :dont, byte()} | {:subneg, byte(), binary()}

  @doc """
  Decodes Telnet data, separating text from protocol commands.

  Returns a map with:
  - `:text` - The actual text content (with IAC sequences removed)
  - `:commands` - List of Telnet commands that need handling

  ## Examples

      iex> Mudc.Telnet.Protocol.decode("Hello")
      %{text: "Hello", commands: []}

      iex> Mudc.Telnet.Protocol.decode(<<255, 251, 1, "Hi">>)
      %{text: "Hi", commands: [{:will, 1}]}
  """
  @spec decode(binary()) :: decoded()
  def decode(data) when is_binary(data) do
    do_decode(data, [], [])
  end

  # Decode implementation - accumulate text and commands
  defp do_decode(<<>>, text_acc, cmd_acc) do
    %{
      text: text_acc |> Enum.reverse() |> IO.iodata_to_binary(),
      commands: Enum.reverse(cmd_acc)
    }
  end

  # IAC IAC -> literal 255 byte
  defp do_decode(<<@iac, @iac, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, [<<@iac>> | text_acc], cmd_acc)
  end

  # IAC WILL option
  defp do_decode(<<@iac, @telnet_will, option, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, text_acc, [{:will, option} | cmd_acc])
  end

  # IAC WONT option
  defp do_decode(<<@iac, @telnet_wont, option, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, text_acc, [{:wont, option} | cmd_acc])
  end

  # IAC DO option
  defp do_decode(<<@iac, @telnet_do, option, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, text_acc, [{:do, option} | cmd_acc])
  end

  # IAC DONT option
  defp do_decode(<<@iac, @telnet_dont, option, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, text_acc, [{:dont, option} | cmd_acc])
  end

  # IAC SB (subnegotiation) - find SE and extract content
  defp do_decode(<<@iac, @telnet_sb, option, rest::binary>>, text_acc, cmd_acc) do
    case find_subneg_end(rest) do
      {content, remaining} ->
        do_decode(remaining, text_acc, [{:subneg, option, content} | cmd_acc])

      nil ->
        # Incomplete subnegotiation, treat as text for now
        do_decode(rest, [<<@iac, @telnet_sb, option>> | text_acc], cmd_acc)
    end
  end

  # Regular text byte
  defp do_decode(<<byte, rest::binary>>, text_acc, cmd_acc) do
    do_decode(rest, [<<byte>> | text_acc], cmd_acc)
  end

  # Find IAC SE sequence for subnegotiation
  defp find_subneg_end(data), do: find_subneg_end(data, [])

  defp find_subneg_end(<<@iac, @telnet_se, rest::binary>>, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp find_subneg_end(<<byte, rest::binary>>, acc) do
    find_subneg_end(rest, [<<byte>> | acc])
  end

  defp find_subneg_end(<<>>, _acc), do: nil

  @doc """
  Handles a Telnet negotiation command and returns the appropriate response.

  By default, we reject most options with DONT/WONT to keep things simple.

  ## Examples

      iex> Mudc.Telnet.Protocol.handle_negotiation({:will, 1})
      {:dont, 1}

      iex> Mudc.Telnet.Protocol.handle_negotiation({:do, 1})
      {:wont, 1}
  """
  @spec handle_negotiation(command()) :: {:do | :dont | :will | :wont, byte()} | nil
  def handle_negotiation({:will, option}) do
    # Server offers to enable option - we decline
    {:dont, option}
  end

  def handle_negotiation({:wont, _option}) do
    # Server refuses option - acknowledge silently
    nil
  end

  def handle_negotiation({:do, option}) do
    # Server requests we enable option - we decline
    {:wont, option}
  end

  def handle_negotiation({:dont, _option}) do
    # Server requests we disable option - acknowledge silently
    nil
  end

  def handle_negotiation({:subneg, _option, _data}) do
    # Ignore subnegotiations for now
    nil
  end

  @doc """
  Encodes a Telnet command into binary format.

  ## Examples

      iex> Mudc.Telnet.Protocol.encode_command({:dont, 1})
      <<255, 254, 1>>

      iex> Mudc.Telnet.Protocol.encode_command({:wont, 24})
      <<255, 252, 24>>
  """
  @spec encode_command({:do | :dont | :will | :wont, byte()}) :: binary()
  def encode_command({:do, option}), do: <<@iac, @telnet_do, option>>
  def encode_command({:dont, option}), do: <<@iac, @telnet_dont, option>>
  def encode_command({:will, option}), do: <<@iac, @telnet_will, option>>
  def encode_command({:wont, option}), do: <<@iac, @telnet_wont, option>>

  @doc """
  Encodes text for sending, escaping IAC bytes (255 -> 255, 255).

  ## Examples

      iex> Mudc.Telnet.Protocol.encode("Hello")
      "Hello"

      iex> Mudc.Telnet.Protocol.encode(<<255, "Hi">>)
      <<255, 255, "Hi">>
  """
  @spec encode(binary()) :: binary()
  def encode(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.flat_map(fn
      @iac -> [@iac, @iac]
      byte -> [byte]
    end)
    |> :binary.list_to_bin()
  end
end
