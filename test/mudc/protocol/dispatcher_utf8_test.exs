defmodule Mudc.Protocol.DispatcherUTF8Test do
  use ExUnit.Case, async: false

  alias Mudc.Protocol.Dispatcher
  alias Mudc.Events.Bus

  setup do
    # Dispatcher is already started by the application, so we don't need to start it
    # Just subscribe to game_text events
    Bus.subscribe(:game_text)

    on_exit(fn ->
      Bus.unsubscribe(:game_text)
      # Flush any remaining messages
      receive do
        _ -> :ok
      after
        0 -> :ok
      end
    end)

    :ok
  end

  describe "UTF-8 text handling" do
    test "handles valid UTF-8 text" do
      valid_utf8 = "Hello 世界! 🎮"

      Dispatcher.process_data(valid_utf8)

      assert_receive {:event, :game_text, {:text, ^valid_utf8}}, 500
    end

    test "handles ASCII text" do
      ascii_text = "Hello, world!"

      Dispatcher.process_data(ascii_text)

      assert_receive {:event, :game_text, {:text, ^ascii_text}}, 500
    end

    test "handles latin-1 encoded text" do
      # Latin-1 encoded text with accented characters
      # These are byte values 0xE9, 0xE8, etc. which are invalid UTF-8
      # but valid latin-1
      # Élves in latin-1
      latin1_bytes = <<0xC9, 0x6C, 0x76, 0x65, 0x73>>

      Dispatcher.process_data(latin1_bytes)

      # Should receive converted UTF-8
      assert_receive {:event, :game_text, {:text, text}}, 500
      assert String.valid?(text)
      # Should contain É (U+00C9)
      assert text =~ "Élves"
    end

    test "handles mixed valid and invalid UTF-8 sequences" do
      # Mix of valid UTF-8 and invalid bytes
      # 0xFF and 0xFE are interpreted as latin-1 'ÿ' and 'þ'
      mixed = "Hello " <> <<0xFF, 0xFE>> <> " World"

      Dispatcher.process_data(mixed)

      assert_receive {:event, :game_text, {:text, text}}, 500
      # Should be valid UTF-8 - latin-1 bytes get converted
      assert String.valid?(text)
      assert text =~ "Hello"
      # The invalid bytes are at the end of what we receive in chunks
      # so we might only get "Hello ÿþ" in first chunk
    end

    test "handles ANSI color codes with UTF-8" do
      # ANSI red color + UTF-8 text
      ansi_utf8 = "\e[31mRed 文字\e[0m"

      Dispatcher.process_data(ansi_utf8)

      assert_receive {:event, :game_text, {:text, ^ansi_utf8}}, 500
    end

    test "handles empty strings" do
      # Empty strings don't generate events in the telnet parser
      # because flush_text skips empty text
      Dispatcher.process_data("")

      # We shouldn't receive any event for empty data
      refute_receive {:event, :game_text, {:text, _}}, 100
    end

    test "handles high-bit bytes in latin-1 range" do
      # Characters like 'ë' (0xEB), 'ñ' (0xF1), etc.
      # ë and ñ in latin-1
      latin1_text = <<0xEB, 0xF1>>

      Dispatcher.process_data(latin1_text)

      assert_receive {:event, :game_text, {:text, text}}, 500
      assert String.valid?(text)
      # ë (0xEB) and ñ (0xF1) converted from latin-1 to UTF-8
      assert text == "ëñ"
    end

    test "preserves valid UTF-8 emoji and special characters" do
      special = "Arrows: → ← ↑ ↓ | Symbols: ★ ☆ ♠ ♣ | Emoji: 🎮 🗡️"

      Dispatcher.process_data(special)

      assert_receive {:event, :game_text, {:text, ^special}}, 500
    end

    test "handles null bytes" do
      with_null = "Hello\x00World"

      Dispatcher.process_data(with_null)

      assert_receive {:event, :game_text, {:text, text}}, 500
      assert String.valid?(text)
    end

    test "handles very long UTF-8 strings" do
      long_text = String.duplicate("日本語 ", 1000)

      Dispatcher.process_data(long_text)

      assert_receive {:event, :game_text, {:text, ^long_text}}, 500
    end
  end

  describe "telnet protocol with UTF-8" do
    test "handles UTF-8 text mixed with telnet commands" do
      # IAC WILL ECHO (255, 251, 1) + UTF-8 text
      data = <<255, 251, 1, "Hello 世界!">>

      Dispatcher.process_data(data)

      # Should receive the text part as valid UTF-8
      assert_receive {:event, :game_text, {:text, "Hello 世界!"}}, 500
    end

    test "handles latin-1 text with telnet commands" do
      # IAC DO GMCP (255, 253, 201) + latin-1 text
      # Élves
      latin1_text = <<0xC9, 0x6C, 0x76, 0x65, 0x73>>
      data = <<255, 253, 201>> <> latin1_text

      Dispatcher.process_data(data)

      assert_receive {:event, :game_text, {:text, text}}, 500
      assert String.valid?(text)
      assert text =~ "Élves"
    end
  end
end
