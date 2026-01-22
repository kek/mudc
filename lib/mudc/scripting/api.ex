defmodule Mudc.Scripting.API do
  @moduledoc """
  Lua API functions for MUD scripting.

  Provides the `mud` table with functions:
  - `mud.send(cmd)` - Send command to server
  - `mud.echo(text)` - Display local text
  - `mud.trigger(pattern, callback)` - Add a trigger
  - `mud.alias(name, callback)` - Add an alias
  - `mud.gag()` - Gag (hide) the current line

  And the `game` table with:
  - `game.vitals()` - Get character vitals
  - `game.room()` - Get current room info
  """

  alias Mudc.Events.Bus
  alias Mudc.State.GameState

  @doc """
  Install the mud and game APIs into a Luerl state.
  """
  def install(lua_state, engine_pid) do
    lua_state
    |> install_mud_api(engine_pid)
    |> install_game_api()
    |> install_print_redirect()
  end

  defp install_mud_api(lua_state, engine_pid) do
    mud_table = [
      {"send", fn args, state -> mud_send(args, state) end},
      {"echo", fn args, state -> mud_echo(args, state) end},
      {"trigger", fn args, state -> mud_trigger(args, state, engine_pid) end},
      {"alias", fn args, state -> mud_alias(args, state, engine_pid) end},
      {"gag", fn args, state -> mud_gag(args, state) end}
    ]

    {:ok, new_state} = :luerl.set_table_keys(["mud"], mud_table, lua_state)
    new_state
  end

  defp install_game_api(lua_state) do
    game_table = [
      {"vitals", fn args, state -> game_vitals(args, state) end},
      {"room", fn args, state -> game_room(args, state) end}
    ]

    {:ok, new_state} = :luerl.set_table_keys(["game"], game_table, lua_state)
    new_state
  end

  defp install_print_redirect(lua_state) do
    # Redirect print to mud.echo
    {:ok, new_state} =
      :luerl.set_table_keys(["print"], fn args, state -> mud_echo(args, state) end, lua_state)

    new_state
  end

  # mud.send(cmd) - Send command to server
  defp mud_send([cmd | _], state) when is_binary(cmd) do
    Mudc.Network.Connection.send_command(cmd)
    {[], state}
  end

  defp mud_send(_, state), do: {[], state}

  # mud.echo(text) - Display local text in UI
  defp mud_echo(args, state) do
    text = Enum.map_join(args, "\t", &to_string/1)
    Bus.publish(:game_text, {:text, "[Lua] " <> text <> "\n"})
    {[], state}
  end

  # mud.trigger(pattern, callback) - Register a trigger
  defp mud_trigger([pattern, callback | _], state, engine_pid) when is_binary(pattern) do
    send(engine_pid, {:register_trigger, pattern, callback})
    {[], state}
  end

  defp mud_trigger(_, state, _engine_pid), do: {[], state}

  # mud.alias(name, callback) - Register an alias
  defp mud_alias([name, callback | _], state, engine_pid) when is_binary(name) do
    send(engine_pid, {:register_alias, name, callback})
    {[], state}
  end

  defp mud_alias(_, state, _engine_pid), do: {[], state}

  # mud.gag() - Mark current line to be hidden
  defp mud_gag(_, state) do
    # Set a flag in the Lua state that the engine can check
    {:ok, new_state} = :luerl.set_table_keys(["_gag_line"], true, state)
    {[], new_state}
  end

  # game.vitals() - Get character vitals
  defp game_vitals(_, state) do
    vitals = GameState.vitals()
    lua_table = map_to_lua_table(vitals)
    {[lua_table], state}
  end

  # game.room() - Get current room info
  defp game_room(_, state) do
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
