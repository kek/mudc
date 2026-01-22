defmodule Mudc.Network.GMCP.Negotiation do
  @moduledoc """
  GMCP handshake and negotiation helpers.

  Provides functions for:
  - Building the Core.Hello message
  - Building Core.Supports.Set message
  - Standard GMCP packages for MUDs
  """

  alias Mudc.Network.GMCP.Parser
  alias Mudc.Network.Telnet.Parser, as: TelnetParser
  alias Mudc.Network.Telnet.Constants, as: TC

  @client_name "Mudc"
  @client_version "0.1.0"

  @doc """
  Build the Core.Hello GMCP message.
  """
  def core_hello do
    Parser.encode("Core.Hello", %{
      "client" => @client_name,
      "version" => @client_version
    })
  end

  @doc """
  Build Core.Supports.Set with the packages we want to receive.
  """
  def core_supports_set(packages \\ default_packages()) do
    Parser.encode("Core.Supports.Set", packages)
  end

  @doc """
  Build Core.Supports.Add for additional packages.
  """
  def core_supports_add(packages) do
    Parser.encode("Core.Supports.Add", packages)
  end

  @doc """
  Build Core.Supports.Remove to stop receiving packages.
  """
  def core_supports_remove(packages) do
    Parser.encode("Core.Supports.Remove", packages)
  end

  @doc """
  Default GMCP packages to request.
  """
  def default_packages do
    [
      "Char 1",
      "Char.Vitals 1",
      "Char.Status 1",
      "Char.StatusVars 1",
      "Room 1",
      "Room.Info 1",
      "Comm 1",
      "Comm.Channel 1"
    ]
  end

  @doc """
  Wrap a GMCP message in Telnet subnegotiation.
  """
  def wrap_subneg(gmcp_message) do
    TelnetParser.subnegotiation(TC.opt_gmcp(), gmcp_message)
  end

  @doc """
  Build DO GMCP response (to server's WILL GMCP).
  """
  def do_gmcp do
    TelnetParser.do_(TC.opt_gmcp())
  end

  @doc """
  Build the initial GMCP handshake sequence.

  Returns binary data to send after receiving WILL GMCP:
  1. DO GMCP
  2. Core.Hello subnegotiation
  3. Core.Supports.Set subnegotiation
  """
  def initial_handshake do
    do_gmcp() <>
      wrap_subneg(core_hello()) <>
      wrap_subneg(core_supports_set())
  end
end
