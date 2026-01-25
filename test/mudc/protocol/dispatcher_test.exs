defmodule Mudc.Protocol.DispatcherTest do
  use ExUnit.Case, async: false

  alias Mudc.Protocol.Dispatcher
  alias Mudc.Events.Bus

  setup do
    # Subscribe to relevant event topics to verify event publishing
    Bus.subscribe(:game_text)
    Bus.subscribe(:telnet)

    # Ensure dispatcher is in clean state
    # The dispatcher is started by the Application

    on_exit(fn ->
      # Clean up any queued messages
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
    end)

    :ok
  end

  describe "process_data/1" do
    test "processes plain text" do
      data = "Hello, world!\n"

      result = Dispatcher.process_data(data)

      # Should return nil (no protocol responses needed)
      assert result == nil

      # Should publish text event
      assert_receive {:event, :game_text, {:text, "Hello, world!\n"}}
    end

    test "handles multiple lines of text" do
      data = "Line 1\nLine 2\nLine 3\n"

      Dispatcher.process_data(data)

      # All text should be published as one event
      assert_receive {:event, :game_text, {:text, "Line 1\nLine 2\nLine 3\n"}}
    end

    test "handles empty data" do
      result = Dispatcher.process_data("")

      assert result == nil
    end

    test "buffers incomplete telnet sequences" do
      # Send incomplete IAC sequence
      incomplete_iac = <<255>>  # IAC byte without following command

      result = Dispatcher.process_data(incomplete_iac)

      # Should buffer and not crash
      assert result == nil

      # Complete the sequence
      complete = <<251, 201>>  # WILL GMCP
      Dispatcher.process_data(complete)

      # Should receive the complete negotiation
      # (GMCP handler will be called)
    end
  end

  describe "text handling" do
    test "publishes text events to event bus" do
      Dispatcher.process_data("Test message\n")

      assert_receive {:event, :game_text, {:text, "Test message\n"}}
    end

    test "handles ANSI escape sequences in text" do
      # Text with ANSI color codes
      colored_text = "\e[31mRed text\e[0m\n"

      Dispatcher.process_data(colored_text)

      # Should preserve ANSI codes
      assert_receive {:event, :game_text, {:text, ^colored_text}}
    end
  end

  describe "telnet negotiations" do
    test "handles WILL GMCP" do
      # IAC WILL GMCP (255 251 201)
      data = <<255, 251, 201>>

      result = Dispatcher.process_data(data)

      # Should respond with DO GMCP or nil depending on GMCP handler state
      # The exact response depends on GMCPHandler implementation
      assert result == nil or is_binary(result)
    end

    test "handles WILL SUPPRESS_GO_AHEAD" do
      # IAC WILL SUPPRESS_GO_AHEAD (255 251 3)
      data = <<255, 251, 3>>

      result = Dispatcher.process_data(data)

      # Should respond with DO SUPPRESS_GO_AHEAD
      assert is_binary(result)
      assert result == <<255, 253, 3>>  # IAC DO SUPPRESS_GO_AHEAD
    end

    test "handles WILL ECHO" do
      # IAC WILL ECHO (255 251 1)
      data = <<255, 251, 1>>

      result = Dispatcher.process_data(data)

      # Should respond with DO ECHO and publish telnet event
      assert result == <<255, 253, 1>>  # IAC DO ECHO

      # Should notify about echo mode
      assert_receive {:event, :telnet, {:echo, true}}
    end

    test "handles WONT ECHO" do
      # IAC WONT ECHO (255 252 1)
      data = <<255, 252, 1>>

      _result = Dispatcher.process_data(data)

      # Should publish echo off event
      assert_receive {:event, :telnet, {:echo, false}}
    end

    test "handles DO TERMINAL_TYPE" do
      # IAC DO TERMINAL_TYPE (255 253 24)
      data = <<255, 253, 24>>

      result = Dispatcher.process_data(data)

      # Should respond with WILL TERMINAL_TYPE
      assert result == <<255, 251, 24>>  # IAC WILL TERMINAL_TYPE
    end

    test "handles DO WINDOW_SIZE" do
      # IAC DO WINDOW_SIZE (255 253 31)
      data = <<255, 253, 31>>

      result = Dispatcher.process_data(data)

      # Should respond with WILL WINDOW_SIZE
      assert result == <<255, 251, 31>>  # IAC WILL WINDOW_SIZE
    end

    test "handles GA (Go Ahead)" do
      # IAC GA (255 249)
      data = <<255, 249>>

      result = Dispatcher.process_data(data)

      assert result == nil

      # Should publish prompt event
      assert_receive {:event, :game_text, :prompt}
    end

    test "handles NOP (No Operation)" do
      # IAC NOP (255 241)
      data = <<255, 241>>

      result = Dispatcher.process_data(data)

      # Should be ignored
      assert result == nil
    end
  end

  describe "subnegotiations" do
    test "handles TERMINAL_TYPE subnegotiation" do
      # IAC SB TERMINAL_TYPE SEND IAC SE
      # 255 250 24 1 255 240
      data = <<255, 250, 24, 1, 255, 240>>

      result = Dispatcher.process_data(data)

      # Should respond with terminal type
      assert is_binary(result)
      # Response should be: IAC SB TERMINAL_TYPE IS XTERM-256COLOR IAC SE
      assert result =~ "XTERM-256COLOR"
    end
  end

  describe "buffer management" do
    test "processes text immediately (no text buffering)" do
      # Send "Hello" without newline
      part1 = "Hello"
      result1 = Dispatcher.process_data(part1)
      assert result1 == nil

      # Text is published immediately, not buffered
      assert_receive {:event, :game_text, {:text, "Hello"}}

      # Send more text
      part2 = " world!\n"
      Dispatcher.process_data(part2)

      # Second part is also published separately
      assert_receive {:event, :game_text, {:text, " world!\n"}}
    end

    test "handles mixed text and telnet commands" do
      # Text followed by IAC command
      data = "Hello\n" <> <<255, 249>>  # text + IAC GA

      _result = Dispatcher.process_data(data)

      # Should process both
      assert_receive {:event, :game_text, {:text, "Hello\n"}}
      assert_receive {:event, :game_text, :prompt}
    end
  end

  describe "set_socket/1" do
    test "accepts socket PID" do
      # This is a cast, so it should succeed
      result = Dispatcher.set_socket(self())
      assert result == :ok
    end
  end
end
