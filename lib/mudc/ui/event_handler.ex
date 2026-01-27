defmodule Mudc.UI.EventHandler do
  @moduledoc """
  Handles keyboard and terminal events for the Mudc UI.

  Translates TermUI events into application messages that can be processed
  by the update function in Mudc.UI.App.

  ## Event Types

  - Enter: Send command
  - Up/Down: Navigate command history
  - Ctrl+Arrow: Send directional commands (north/south/west/east)
  - Left/Right: Horizontal scroll on debug screen
  - Numpad: Send directional commands and actions
  - Page Up/Down: Scroll game text
  - F3/F4/F5: Switch screens
  - Ctrl+F5: Recompile code
  - Ctrl+C/Ctrl+Q: Quit
  """

  alias TermUI.Event

  @doc """
  Converts a TermUI event into an application message.

  Returns one of:
  - `{:msg, message}` - A message to be processed by update/2
  - `:ignore` - Event should be ignored
  """
  def event_to_msg(%Event.Key{key: :enter}, state) do
    {:msg, {:send_command, state.input_buffer}}
  end

  # History navigation (up/down without modifiers)
  def event_to_msg(%Event.Key{key: :up, modifiers: []}, %{history: history})
      when history != [] do
    {:msg, :history_prev}
  end

  def event_to_msg(%Event.Key{key: :down, modifiers: []}, %{history_index: idx})
      when not is_nil(idx) do
    {:msg, :history_next}
  end

  # Ctrl+Arrow for directional movement
  def event_to_msg(%Event.Key{key: :up, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "north"}}
  end

  def event_to_msg(%Event.Key{key: :down, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "south"}}
  end

  def event_to_msg(%Event.Key{key: :left, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "west"}}
  end

  def event_to_msg(%Event.Key{key: :right, modifiers: [:ctrl]}, _state) do
    {:msg, {:send_command, "east"}}
  end

  # Left/Right arrows for horizontal scrolling on debug screen
  def event_to_msg(%Event.Key{key: :left, modifiers: []}, %{current_screen: :dog}) do
    {:msg, {:horizontal_scroll, -5}}
  end

  def event_to_msg(%Event.Key{key: :right, modifiers: []}, %{current_screen: :dog}) do
    {:msg, {:horizontal_scroll, 5}}
  end

  # Ignore left/right on other screens (they're used for cursor movement in input)
  def event_to_msg(%Event.Key{key: key, modifiers: []}, _state) when key in [:left, :right] do
    :ignore
  end

  # Numpad commands (for terminals with application keypad mode)
  def event_to_msg(%Event.Key{key: :kp_up}, _state), do: {:msg, {:send_command, "north"}}
  def event_to_msg(%Event.Key{key: :kp_down}, _state), do: {:msg, {:send_command, "south"}}
  def event_to_msg(%Event.Key{key: :kp_left}, _state), do: {:msg, {:send_command, "west"}}
  def event_to_msg(%Event.Key{key: :kp_right}, _state), do: {:msg, {:send_command, "east"}}
  def event_to_msg(%Event.Key{key: :kp_7}, _state), do: {:msg, {:send_command, "stand"}}
  def event_to_msg(%Event.Key{key: :kp_8}, _state), do: {:msg, {:send_command, "north"}}
  def event_to_msg(%Event.Key{key: :kp_9}, _state), do: {:msg, {:send_command, "up"}}
  def event_to_msg(%Event.Key{key: :kp_4}, _state), do: {:msg, {:send_command, "west"}}
  def event_to_msg(%Event.Key{key: :kp_5}, _state), do: {:msg, {:send_command, "look"}}
  def event_to_msg(%Event.Key{key: :kp_6}, _state), do: {:msg, {:send_command, "east"}}
  def event_to_msg(%Event.Key{key: :kp_1}, _state), do: {:msg, {:send_command, "rest"}}
  def event_to_msg(%Event.Key{key: :kp_2}, _state), do: {:msg, {:send_command, "south"}}
  def event_to_msg(%Event.Key{key: :kp_3}, _state), do: {:msg, {:send_command, "down"}}
  def event_to_msg(%Event.Key{key: :kp_plus}, _state), do: {:msg, {:send_command, "score"}}
  def event_to_msg(%Event.Key{key: :kp_minus}, _state), do: {:msg, {:send_command, "info"}}
  def event_to_msg(%Event.Key{key: :kp_multiply}, _state), do: {:msg, {:send_command, "x"}}

  def event_to_msg(%Event.Key{key: :backspace}, _state), do: {:msg, :backspace}

  # Ctrl+C and Ctrl+Q quit
  def event_to_msg(%Event.Key{key: key, modifiers: [:ctrl]}, _state) when key in ["c", "q"] do
    {:msg, :quit}
  end

  def event_to_msg(%Event.Key{key: key}, _state) when key in ["c", "q"] do
    {:msg, {:char, key}}
  end

  # Ctrl+L is ignored (terminal clear)
  def event_to_msg(%Event.Key{key: "l", modifiers: [:ctrl]}, _state), do: :ignore

  def event_to_msg(%Event.Key{key: "l"}, _state), do: {:msg, {:char, "l"}}

  # Function keys - Screen switching
  def event_to_msg(%Event.Key{key: :f3}, _state), do: {:msg, {:switch_screen, :game}}
  def event_to_msg(%Event.Key{key: :f4}, _state), do: {:msg, {:switch_screen, :dog}}
  def event_to_msg(%Event.Key{key: :f5, modifiers: [:ctrl]}, _state), do: {:msg, :recompile}
  def event_to_msg(%Event.Key{key: :f5}, _state), do: {:msg, {:switch_screen, :cat}}

  # Page Up/Down - scrolling
  def event_to_msg(%Event.Key{key: :page_up}, state),
    do: {:msg, {:scroll, -state.viewport_height}}

  def event_to_msg(%Event.Key{key: :page_down}, state),
    do: {:msg, {:scroll, state.viewport_height}}

  # Regular character input
  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:msg, {:char, char}}
  end

  # Terminal resize
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(_event, _state), do: :ignore
end
