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

  alias Mudc.Scripting.APICallbacks

  @doc """
  Install the mud and game APIs into a Luerl state.
  """
  def install(lua_state, engine_pid) do
    lua_state
    |> install_internal_functions(engine_pid)
    |> install_mud_api_via_lua()
    |> install_game_api_via_lua()
    |> install_print_redirect()
  end

  # Install internal Erlang functions that Lua wrappers will call
  defp install_internal_functions(lua_state, engine_pid) do
    # Store engine_pid in Lua state for callbacks to use
    {:ok, state1} = :luerl.set_table_keys(["_mudc_engine_pid"], engine_pid, lua_state)

    # Create _mudc_internal table first
    {:ok, _result, state2} = :luerl.do("_mudc_internal = {}", state1)

    # Install internal callback functions using MFA tuples
    # The third parameter in MFA tuple is "extra data" that gets passed as first arg to the function
    state3 = install_mfa(state2, ["_mudc_internal", "send"], APICallbacks, :mud_send, :undefined)
    state4 = install_mfa(state3, ["_mudc_internal", "echo"], APICallbacks, :mud_echo, :undefined)

    # For trigger and alias, pass engine_pid as the extra data parameter
    state5 =
      install_mfa(state4, ["_mudc_internal", "trigger"], APICallbacks, :mud_trigger, engine_pid)

    state6 =
      install_mfa(state5, ["_mudc_internal", "alias"], APICallbacks, :mud_alias, engine_pid)

    state7 = install_mfa(state6, ["_mudc_internal", "gag"], APICallbacks, :mud_gag, :undefined)

    state8 =
      install_mfa(state7, ["_mudc_internal", "vitals"], APICallbacks, :game_vitals, :undefined)

    install_mfa(state8, ["_mudc_internal", "room"], APICallbacks, :game_room, :undefined)
  end

  # Helper to install a function using MFA tuple format
  defp install_mfa(lua_state, path, module, function, extra_data) do
    # Luerl expects functions as {:erl_mfa, module_atom, function_atom, extra_data} tuples
    # The extra_data is passed as the first argument to the function
    # Elixir module names need to be converted to Erlang atom format
    erlang_module = Module.concat([module])
    mfa = {:erl_mfa, erlang_module, function, extra_data}

    case :luerl.set_table_keys(path, mfa, lua_state) do
      {:ok, new_state} ->
        new_state

      {:error, reason} ->
        require Logger
        Logger.error("Failed to install function at #{inspect(path)}: #{inspect(reason)}")
        lua_state
    end
  end

  # Create Lua wrapper functions that call the internal Erlang functions
  defp install_mud_api_via_lua(lua_state) do
    lua_code = """
    mud = {
      send = function(cmd)
        return _mudc_internal.send(cmd)
      end,

      echo = function(...)
        return _mudc_internal.echo(...)
      end,

      trigger = function(pattern, callback)
        return _mudc_internal.trigger(pattern, callback)
      end,

      alias = function(name, callback)
        return _mudc_internal.alias(name, callback)
      end,

      gag = function()
        return _mudc_internal.gag()
      end
    }
    """

    case :luerl.do(lua_code, lua_state) do
      {:ok, _result, new_state} ->
        new_state

      {:error, reason} ->
        require Logger
        Logger.error("Failed to install mud API: #{inspect(reason)}")
        lua_state
    end
  end

  defp install_game_api_via_lua(lua_state) do
    lua_code = """
    game = {
      vitals = function()
        return _mudc_internal.vitals()
      end,

      room = function()
        return _mudc_internal.room()
      end
    }
    """

    case :luerl.do(lua_code, lua_state) do
      {:ok, _result, new_state} ->
        new_state

      {:error, reason} ->
        require Logger
        Logger.error("Failed to install game API: #{inspect(reason)}")
        lua_state
    end
  end

  defp install_print_redirect(lua_state) do
    # Redirect print to call _mudc_internal.echo
    lua_code = """
    print = function(...)
      return _mudc_internal.echo(...)
    end
    """

    case :luerl.do(lua_code, lua_state) do
      {:ok, _result, new_state} ->
        new_state

      {:error, reason} ->
        require Logger
        Logger.error("Failed to install print redirect: #{inspect(reason)}")
        lua_state
    end
  end

  # Note: The actual callback implementations are in APICallbacks module
end
