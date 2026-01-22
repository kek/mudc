defmodule Mudc.Telnet.ProtocolTest do
  use ExUnit.Case, async: true

  alias Mudc.Telnet.Protocol

  describe "decode/1" do
    test "decodes plain text without Telnet commands" do
      assert %{text: "Hello", commands: []} = Protocol.decode("Hello")
    end

    test "decodes IAC IAC as literal 255 byte" do
      assert %{text: <<255>>, commands: []} = Protocol.decode(<<255, 255>>)
    end

    test "decodes IAC WILL option" do
      assert %{text: "", commands: [{:will, 1}]} = Protocol.decode(<<255, 251, 1>>)
    end

    test "decodes IAC WONT option" do
      assert %{text: "", commands: [{:wont, 1}]} = Protocol.decode(<<255, 252, 1>>)
    end

    test "decodes IAC DO option" do
      assert %{text: "", commands: [{:do, 1}]} = Protocol.decode(<<255, 253, 1>>)
    end

    test "decodes IAC DONT option" do
      assert %{text: "", commands: [{:dont, 1}]} = Protocol.decode(<<255, 254, 1>>)
    end

    test "decodes text with embedded Telnet command" do
      assert %{text: "Hi", commands: [{:will, 1}]} =
               Protocol.decode(<<255, 251, 1, "Hi">>)
    end

    test "decodes multiple Telnet commands" do
      result = Protocol.decode(<<255, 251, 1, 255, 253, 2>>)
      assert %{text: "", commands: commands} = result
      assert {:will, 1} in commands
      assert {:do, 2} in commands
      assert length(commands) == 2
    end

    test "decodes subnegotiation" do
      # IAC SB option data IAC SE
      data = <<255, 250, 24, "some data", 255, 240>>
      assert %{text: "", commands: [{:subneg, 24, "some data"}]} = Protocol.decode(data)
    end

    test "handles incomplete subnegotiation" do
      # IAC SB without SE - treat as text for now
      data = <<255, 250, 24, "incomplete">>
      result = Protocol.decode(data)
      assert result.text != ""
    end
  end

  describe "handle_negotiation/1" do
    test "responds to WILL with DONT" do
      assert {:dont, 1} = Protocol.handle_negotiation({:will, 1})
    end

    test "responds to DO with WONT" do
      assert {:wont, 1} = Protocol.handle_negotiation({:do, 1})
    end

    test "responds to WONT with nil" do
      assert nil == Protocol.handle_negotiation({:wont, 1})
    end

    test "responds to DONT with nil" do
      assert nil == Protocol.handle_negotiation({:dont, 1})
    end

    test "responds to subnegotiation with nil" do
      assert nil == Protocol.handle_negotiation({:subneg, 1, "data"})
    end
  end

  describe "encode_command/1" do
    test "encodes DO command" do
      assert <<255, 253, 1>> = Protocol.encode_command({:do, 1})
    end

    test "encodes DONT command" do
      assert <<255, 254, 1>> = Protocol.encode_command({:dont, 1})
    end

    test "encodes WILL command" do
      assert <<255, 251, 1>> = Protocol.encode_command({:will, 1})
    end

    test "encodes WONT command" do
      assert <<255, 252, 1>> = Protocol.encode_command({:wont, 1})
    end
  end

  describe "encode/1" do
    test "encodes plain text unchanged" do
      assert "Hello" = Protocol.encode("Hello")
    end

    test "escapes IAC byte (255)" do
      assert <<255, 255, "Hi">> = Protocol.encode(<<255, "Hi">>)
    end

    test "escapes multiple IAC bytes" do
      assert <<255, 255, 255, 255>> = Protocol.encode(<<255, 255>>)
    end

    test "handles empty string" do
      assert "" = Protocol.encode("")
    end
  end
end
