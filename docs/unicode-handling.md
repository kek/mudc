# Unicode and Character Encoding Handling

This document explains how Mudc handles various character encodings, particularly UTF-8 and Latin-1, which are common in MUD servers.

## Background

MUD servers can send text in different character encodings:
- Modern servers typically use UTF-8
- Older servers often use Latin-1 (ISO-8859-1) or other single-byte encodings
- Some servers mix encodings or send invalid UTF-8 sequences

Elixir strings are always UTF-8, so we need to handle non-UTF-8 data gracefully.

## Implementation

### 1. Protocol Layer (`Mudc.Protocol.Dispatcher`)

The dispatcher scrubs incoming text to ensure it's valid UTF-8:

```elixir
defp scrub_utf8(binary) when is_binary(binary) do
  if String.valid?(binary) do
    binary
  else
    # Try converting from Latin-1 first (common for older MUDs)
    case :unicode.characters_to_binary(binary, :latin1, :utf8) do
      result when is_binary(result) -> result
      _ -> scrub_byte_by_byte(binary)
    end
  end
end
```

**Strategy:**
1. Check if the binary is already valid UTF-8
2. If not, attempt Latin-1 to UTF-8 conversion (handles most legacy MUDs)
3. If that fails, convert byte-by-byte, treating each byte as Latin-1

This ensures all text passed to the UI layer is valid UTF-8.

### 2. Socket Layer (`Mudc.Network.Connection.Socket`)

The TCP socket uses standard `:binary` mode:

```elixir
opts = [
  :binary,
  active: :once,
  packet: :raw,
  nodelay: true
]
```

This preserves raw bytes from the server, allowing the protocol layer to handle encoding.

### 3. Logging Layer (`Mudc.Logging.GameLogger`)

The game logger:
- Opens files with `:utf8` encoding
- Uses safe write operations that catch termination errors
- Validates that the file descriptor is alive before writing in `terminate/2`

```elixir
defp safe_write(file, data) do
  try do
    case IO.write(file, data) do
      :ok -> {:ok, byte_size(data)}
      {:error, _} = error -> error
    end
  catch
    :error, {:terminated, _} -> {:error, :terminated}
    :error, reason -> {:error, reason}
  end
end
```

This prevents crashes when:
- The file process terminates unexpectedly
- The file descriptor becomes invalid
- Unicode characters can't be written (though this shouldn't happen with UTF-8 files)

### 4. UI Layer (`Mudc.UI.AnsiParser`)

The ANSI parser works directly with UTF-8 strings using:
- `String.valid?/1` for validation
- Binary pattern matching for ANSI escape sequences
- `binary_part/3` which is safe with UTF-8 when used on regex match boundaries

The parser preserves all valid UTF-8 characters, including:
- Emoji: 🎮 🗡️ ⚔️
- Box drawing: ┌─┐│└┘
- Arrows: → ← ↑ ↓
- Symbols: ★ ☆ ♠ ♣
- Accented characters: é è ñ ë

## Common Encodings

### UTF-8
- Variable-length encoding (1-4 bytes per character)
- Backward compatible with ASCII (0x00-0x7F)
- Handles all Unicode characters
- **Already supported** - passes through unchanged

### Latin-1 (ISO-8859-1)
- Single-byte encoding (0x00-0xFF maps to Unicode U+0000-U+00FF)
- Common in European MUDs
- Characters 0x80-0xFF include: é, ñ, ö, ü, etc.
- **Automatically converted** to UTF-8

### CP-437 (DOS/OEM)
- Used by some older MUDs for box drawing
- Characters 0x80-0xFF have different meanings than Latin-1
- **Not currently supported** - treated as Latin-1

## Testing

See `test/mudc/protocol/dispatcher_utf8_test.exs` for comprehensive tests covering:
- Valid UTF-8 (including emoji and multi-byte characters)
- Latin-1 encoded text
- Mixed valid/invalid sequences
- ANSI escape codes with UTF-8
- Telnet protocol negotiation with UTF-8 text
- Edge cases (empty strings, null bytes, very long strings)

## Known Limitations

1. **CP-437 Box Drawing**: Some older MUDs use CP-437 encoding for box drawing characters. These will be incorrectly converted as Latin-1. Future enhancement could detect and convert CP-437.

2. **Partial UTF-8 Sequences**: If a UTF-8 sequence is split across TCP packets, the Telnet parser buffers incomplete data. However, if the server sends an incomplete UTF-8 sequence at the end of a logical chunk, it will be treated as Latin-1.

3. **Terminal Font Support**: The terminal must have a font that supports Unicode characters. Most modern terminals do, but some characters may display as boxes or question marks if the font lacks glyphs.

## Debugging Unicode Issues

If you see garbled text or blank spaces:

1. **Check the game log**: `~/.config/mudc/game.log` contains raw logged data
2. **Check terminal encoding**: Ensure your terminal is set to UTF-8
3. **Check terminal font**: Use a Unicode-capable font (Menlo, Monaco, Consolas, etc.)
4. **Enable debug logging**:
   ```elixir
   # In IEx
   Logger.configure(level: :debug)
   ```
   You'll see messages like:
   ```
   [debug] Invalid UTF-8/latin-1 sequence detected, scrubbing
   ```

## Future Enhancements

- [ ] Add CP-437 detection and conversion for box drawing
- [ ] Add configuration option to select preferred encoding
- [ ] Add encoding detection heuristics
- [ ] Add per-server encoding configuration
- [ ] Add UTF-8 validation stats/metrics