defmodule MudcTest do
  use ExUnit.Case

  alias Mudc.Network.Telnet.Parser, as: TelnetParser
  alias Mudc.Network.GMCP.Parser, as: GMCPParser

  describe "Telnet Parser" do
    test "parses plain text" do
      {:ok, events, rest} = TelnetParser.parse("Hello World")
      assert events == [{:text, "Hello World"}]
      assert rest == <<>>
    end

    test "parses IAC WILL" do
      # IAC WILL GMCP
      {:ok, events, rest} = TelnetParser.parse(<<255, 251, 201>>)
      assert events == [{:will, 201}]
      assert rest == <<>>
    end

    test "parses IAC DO" do
      # IAC DO ECHO
      {:ok, events, rest} = TelnetParser.parse(<<255, 253, 1>>)
      assert events == [{:do, 1}]
      assert rest == <<>>
    end

    test "parses mixed text and commands" do
      # "Hi" + IAC WILL GMCP + "There"
      data = "Hi" <> <<255, 251, 201>> <> "There"
      {:ok, events, rest} = TelnetParser.parse(data)

      assert events == [{:text, "Hi"}, {:will, 201}, {:text, "There"}]
      assert rest == <<>>
    end

    test "handles escaped IAC" do
      # IAC IAC should become a single 255 byte
      {:ok, events, rest} = TelnetParser.parse(<<255, 255>>)
      assert events == [{:text, <<255>>}]
      assert rest == <<>>
    end

    test "parses subnegotiation" do
      # IAC SB GMCP "data" IAC SE
      data = <<255, 250, 201>> <> "test data" <> <<255, 240>>
      {:ok, events, rest} = TelnetParser.parse(data)

      assert events == [{:subneg, 201, "test data"}]
      assert rest == <<>>
    end

    test "handles incomplete IAC sequence" do
      {:ok, events, rest} = TelnetParser.parse(<<255>>)
      assert events == []
      assert rest == <<255>>
    end

    test "handles incomplete subnegotiation" do
      # IAC SB GMCP "partial" (no IAC SE)
      data = <<255, 250, 201>> <> "partial"
      {:ok, events, rest} = TelnetParser.parse(data)

      assert events == []
      assert rest == <<255, 250, 201>> <> "partial"
    end
  end

  describe "GMCP Parser" do
    test "parses message with JSON data" do
      {:ok, package, data} = GMCPParser.parse(~s|Char.Vitals {"hp":100,"maxhp":200}|)
      assert package == "Char.Vitals"
      assert data == %{"hp" => 100, "maxhp" => 200}
    end

    test "parses message without data" do
      {:ok, package, data} = GMCPParser.parse("Core.Ping")
      assert package == "Core.Ping"
      assert data == nil
    end

    test "handles invalid JSON" do
      {:error, {:json_decode_error, _reason, _str}} =
        GMCPParser.parse("Char.Vitals {invalid}")
    end

    test "encodes message with data" do
      encoded = GMCPParser.encode("Core.Hello", %{"client" => "Test"})
      assert encoded == ~s|Core.Hello {"client":"Test"}|
    end

    test "encodes message without data" do
      encoded = GMCPParser.encode("Core.Ping", nil)
      assert encoded == "Core.Ping"
    end
  end
end
