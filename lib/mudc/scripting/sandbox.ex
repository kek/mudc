defmodule Mudc.Scripting.Sandbox do
  @moduledoc """
  Security sandbox for Lua scripts.

  Removes dangerous functions from the Lua environment to prevent:
  - File system access (io, file)
  - Process execution (os.execute, os.exit)
  - Loading arbitrary code (loadfile, dofile)
  - Debug functions (debug library)

  Keeps safe functions for scripting:
  - String manipulation
  - Table operations
  - Math functions
  - Basic Lua (print -> redirected to mud.echo)
  """

  @doc """
  Apply sandbox restrictions to a Luerl state.
  """
  def apply(lua_state) do
    # Remove dangerous modules/functions
    lua_state
    |> remove_dangerous_globals()
    |> remove_io_module()
    |> remove_os_dangerous()
    |> remove_debug_module()
    |> remove_load_functions()
  end

  defp remove_dangerous_globals(lua_state) do
    dangerous = [
      "dofile",
      "loadfile",
      "load",
      "loadstring"
    ]

    Enum.reduce(dangerous, lua_state, fn name, state ->
      {:ok, new_state} = :luerl.set_table_keys([name], nil, state)
      new_state
    end)
  end

  defp remove_io_module(lua_state) do
    {:ok, new_state} = :luerl.set_table_keys(["io"], nil, lua_state)
    new_state
  end

  defp remove_os_dangerous(lua_state) do
    # Keep safe os functions like os.time, os.date, os.difftime
    # Remove dangerous ones
    dangerous = ["execute", "exit", "getenv", "remove", "rename", "setlocale", "tmpname"]

    Enum.reduce(dangerous, lua_state, fn name, state ->
      {:ok, new_state} = :luerl.set_table_keys(["os", name], nil, state)
      new_state
    end)
  end

  defp remove_debug_module(lua_state) do
    {:ok, new_state} = :luerl.set_table_keys(["debug"], nil, lua_state)
    new_state
  end

  defp remove_load_functions(lua_state) do
    # package.loadlib is dangerous
    {:ok, new_state} = :luerl.set_table_keys(["package", "loadlib"], nil, lua_state)
    new_state
  end
end
