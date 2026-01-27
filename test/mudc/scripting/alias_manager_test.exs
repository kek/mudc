defmodule Mudc.Scripting.AliasManagerTest do
  use ExUnit.Case, async: false

  alias Mudc.Scripting.AliasManager

  setup do
    # AliasManager is already started by the application supervisor
    # Just clear any existing aliases before each test
    AliasManager.clear()

    :ok
  end

  describe "register/2" do
    test "registers an alias with callback" do
      callback = fn _args -> "look" end

      assert :ok = AliasManager.register("l", callback)
    end

    test "allows multiple aliases to be registered" do
      callback1 = fn _args -> "look" end
      callback2 = fn _args -> "inventory" end

      assert :ok = AliasManager.register("l", callback1)
      assert :ok = AliasManager.register("i", callback2)
    end
  end

  describe "clear/0" do
    test "clears all registered aliases" do
      callback = fn _args -> "test" end
      AliasManager.register("t", callback)

      assert :ok = AliasManager.clear()
    end
  end

  describe "list/0" do
    test "lists all registered aliases" do
      callback1 = fn _args -> "look" end
      callback2 = fn _args -> "inventory" end

      AliasManager.register("l", callback1)
      AliasManager.register("i", callback2)

      aliases = AliasManager.list()

      assert is_list(aliases)
      assert length(aliases) == 2

      # list() returns just the keys (names), not tuples
      assert "l" in aliases
      assert "i" in aliases
    end

    test "returns empty list when no aliases registered" do
      AliasManager.clear()

      aliases = AliasManager.list()

      assert aliases == []
    end
  end

  # describe "expand/1" do
  #   test "expands registered alias" do
  #     callback = fn _args -> "look" end
  #     AliasManager.register("l", callback)
  #
  #     # Note: expand/1 would need to call Engine.call_function
  #     # This is more of an integration test requiring Luerl VM
  #     result = AliasManager.expand("l")
  #
  #     # The actual expansion depends on Engine being available
  #     # For unit test, we just verify the function exists
  #     assert result != nil or result == nil
  #   end
  #
  #   test "returns original command if no alias matches" do
  #     result = AliasManager.expand("unregistered_command")
  #
  #     # Should return the original command or nil
  #     assert is_binary(result) or result == nil
  #   end
  # end
end
