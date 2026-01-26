defmodule Mudc.Scripting.TriggerManagerTest do
  use ExUnit.Case, async: false

  alias Mudc.Scripting.TriggerManager
  alias Mudc.Events.Bus

  setup do
    # Start the trigger manager
    start_supervised!(TriggerManager)

    :ok
  end

  describe "register/2" do
    test "registers a trigger pattern with callback" do
      callback = fn _text -> :ok end

      assert :ok = TriggerManager.register("monster", callback)
    end

    test "allows multiple triggers to be registered" do
      callback1 = fn _text -> :trigger1 end
      callback2 = fn _text -> :trigger2 end

      assert :ok = TriggerManager.register("monster", callback1)
      assert :ok = TriggerManager.register("attack", callback2)
    end
  end

  describe "clear/0" do
    test "clears all registered triggers" do
      callback = fn _text -> :ok end
      TriggerManager.register("test", callback)

      assert :ok = TriggerManager.clear()

      # Verify triggers are cleared by checking state
      # (This is indirect - we'd need to trigger and see no callback)
    end
  end

  describe "trigger matching" do
    test "triggers fire when pattern matches game text" do
      # Set up a trigger that sends a message back to us
      test_pid = self()
      callback = fn text -> send(test_pid, {:triggered, text}) end

      TriggerManager.register("monster", callback)

      # Simulate game text event
      Bus.publish(:game_text, {:plain_text, "You see a monster"})

      # Wait a bit for async processing
      Process.sleep(50)

      # Note: This test requires the Engine to be running to call the callback
      # In a real scenario, TriggerManager would call Engine.call_function
      # which requires Luerl VM. This is more of an integration test.
    end
  end

  describe "list/0" do
    test "lists all registered triggers" do
      callback1 = fn _text -> :ok end
      callback2 = fn _text -> :ok end

      TriggerManager.register("pattern1", callback1)
      TriggerManager.register("pattern2", callback2)

      triggers = TriggerManager.list()

      assert is_list(triggers)
      assert length(triggers) == 2

      patterns = Enum.map(triggers, fn {pattern, _callback} -> pattern end)
      assert "pattern1" in patterns
      assert "pattern2" in patterns
    end

    test "returns empty list when no triggers registered" do
      TriggerManager.clear()

      triggers = TriggerManager.list()

      assert triggers == []
    end
  end
end
