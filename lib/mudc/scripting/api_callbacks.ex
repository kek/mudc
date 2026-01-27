defmodule Mudc.Scripting.APICallbacks do
  @moduledoc """
  Callback functions for Lua API.

  These are module functions that Luerl can call directly.
  Each function receives (args, lua_state) and returns {result, new_state}.
  """

  alias Mudc.Network.Connection
  alias Mudc.Events.Bus
  alias Mudc.State.GameState

  # mud.send(cmd) - Send command to server
  # Luerl MFA convention: first arg is the extra data (unused), second is args list, third is state
  def mud_send(_extra, [cmd | _], state) when is_binary(cmd) do
    Connection.send_command(cmd)
    {[], state}
  end

  def mud_send(_extra, _, state), do: {[], state}

  # mud.echo(text) - Display local text in UI
  # Luerl MFA convention: first arg is the extra data (unused), second is args list, third is state
  def mud_echo(_extra, args, state) do
    text = Enum.map_join(args, "\t", &to_string/1)
    Bus.publish(:game_text, {:text, "[Lua] " <> text <> "\n"})
    {[], state}
  end

  # mud.trigger(pattern, callback) - Register a trigger
  # Luerl MFA convention: first arg is the extra data (engine_pid), second is args list, third is state
  def mud_trigger(engine_pid, [pattern, callback | _], state) when is_binary(pattern) do
    send(engine_pid, {:register_trigger, pattern, callback})
    {[], state}
  end

  def mud_trigger(_engine_pid, _, state), do: {[], state}

  # mud.alias(name, callback) - Register an alias
  # Luerl MFA convention: first arg is the extra data (engine_pid), second is args list, third is state
  def mud_alias(engine_pid, [name, callback | _], state) when is_binary(name) do
    send(engine_pid, {:register_alias, name, callback})
    {[], state}
  end

  def mud_alias(_engine_pid, _, state), do: {[], state}

  # mud.gag() - Mark current line to be hidden
  # Luerl MFA convention: first arg is the extra data (unused), second is args list, third is state
  def mud_gag(_extra, _args, state) do
    # Set a flag in the Lua state that the engine can check
    {:ok, new_state} = :luerl.set_table_keys(["_gag_line"], true, state)
    {[], new_state}
  end

  # game.vitals() - Get character vitals
  # Luerl MFA convention: first arg is the extra data (unused), second is args list, third is state
  def game_vitals(_extra, _args, state) do
    vitals = GameState.vitals()
    lua_table = map_to_lua_table(vitals)
    {[lua_table], state}
  end

  # game.room() - Get current room info
  # Luerl MFA convention: first arg is the extra data (unused), second is args list, third is state
  def game_room(_extra, _args, state) do
    room = GameState.room()
    lua_table = map_to_lua_table(room)
    {[lua_table], state}
  end

  # Convert Elixir map to Lua table format
  defp map_to_lua_table(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), convert_value(v)} end)
  end

  defp convert_value(v) when is_map(v), do: map_to_lua_table(v)
  defp convert_value(v) when is_list(v), do: Enum.map(v, &convert_value/1)
  defp convert_value(v), do: v
end
