defmodule Mudc.State.GameStateTest do
  use ExUnit.Case, async: false

  alias Mudc.State.GameState
  alias Mudc.Events.Bus

  setup do
    # Subscribe to state change events
    Bus.subscribe(:state_changed)

    # GameState is started by the Application
    # Clean up any existing state
    :ets.delete_all_objects(GameState)

    on_exit(fn ->
      # Clean up messages
      receive do
        _ -> :ok
      after
        0 -> :ok
      end

      # Clean up state
      :ets.delete_all_objects(GameState)
    end)

    :ok
  end

  describe "get/1" do
    test "returns nil for missing keys" do
      result = GameState.get(:nonexistent)
      assert result == nil
    end

    test "returns value for existing keys" do
      # Insert directly into ETS
      :ets.insert(GameState, {:test_key, "test_value"})

      result = GameState.get(:test_key)
      assert result == "test_value"
    end

    test "handles map values" do
      test_map = %{"hp" => 100, "maxhp" => 120}
      :ets.insert(GameState, {:vitals, test_map})

      result = GameState.get(:vitals)
      assert result == test_map
    end
  end

  describe "get/2" do
    test "returns nil for missing keys" do
      result = GameState.get(:nonexistent, "subkey")
      assert result == nil
    end

    test "returns nil for missing subkeys" do
      :ets.insert(GameState, {:vitals, %{"hp" => 100}})

      result = GameState.get(:vitals, "nonexistent")
      assert result == nil
    end

    test "returns nested value" do
      :ets.insert(GameState, {:vitals, %{"hp" => 100, "maxhp" => 120}})

      result = GameState.get(:vitals, "hp")
      assert result == 100
    end

    test "handles non-map values gracefully" do
      :ets.insert(GameState, {:test_key, "not a map"})

      result = GameState.get(:test_key, "subkey")
      assert result == nil
    end
  end

  describe "all/0" do
    test "returns empty map when no state" do
      result = GameState.all()
      assert result == %{}
    end

    test "returns all state as map" do
      :ets.insert(GameState, {:vitals, %{"hp" => 100}})
      :ets.insert(GameState, {:room, %{"name" => "Test Room"}})

      result = GameState.all()

      assert result == %{
               vitals: %{"hp" => 100},
               room: %{"name" => "Test Room"}
             }
    end
  end

  describe "convenience functions" do
    test "vitals/0 returns vitals or empty map" do
      assert GameState.vitals() == %{}

      :ets.insert(GameState, {:vitals, %{"hp" => 100}})
      assert GameState.vitals() == %{"hp" => 100}
    end

    test "room/0 returns room or empty map" do
      assert GameState.room() == %{}

      :ets.insert(GameState, {:room, %{"name" => "Test Room"}})
      assert GameState.room() == %{"name" => "Test Room"}
    end

    test "status/0 returns status or empty map" do
      assert GameState.status() == %{}

      :ets.insert(GameState, {:status, %{"level" => 10}})
      assert GameState.status() == %{"level" => 10}
    end
  end

  describe "GMCP event handling" do
    test "handles gmcp_vitals events" do
      vitals_data = %{"hp" => 100, "maxhp" => 120, "mana" => 50}

      # Send GMCP vitals event
      send(GameState, {:event, :gmcp_vitals, vitals_data})

      # Give it time to process
      Process.sleep(10)

      # Should update state
      result = GameState.get(:vitals)
      assert result == vitals_data

      # Should publish state change event
      assert_receive {:event, :state_changed, {:vitals, ^vitals_data}}
    end

    test "merges vitals updates" do
      # Set initial vitals
      initial = %{"hp" => 100, "maxhp" => 120}
      :ets.insert(GameState, {:vitals, initial})

      # Send update with partial data
      update = %{"hp" => 80}
      send(GameState, {:event, :gmcp_vitals, update})

      Process.sleep(10)

      # Should merge, not replace
      result = GameState.get(:vitals)
      assert result == %{"hp" => 80, "maxhp" => 120}
    end

    test "handles gmcp_room events" do
      room_data = %{"name" => "A Dark Tunnel", "exits" => ["north", "south"]}

      send(GameState, {:event, :gmcp_room, room_data})

      Process.sleep(10)

      result = GameState.get(:room)
      assert result == room_data

      assert_receive {:event, :state_changed, {:room, ^room_data}}
    end

    test "handles gmcp_status events" do
      status_data = %{"level" => 10, "class" => "Warrior"}

      send(GameState, {:event, :gmcp_status, status_data})

      Process.sleep(10)

      result = GameState.get(:status)
      assert result == status_data

      assert_receive {:event, :state_changed, {:status, ^status_data}}
    end

    test "merges status updates" do
      # Set initial status
      initial = %{"level" => 10, "class" => "Warrior"}
      :ets.insert(GameState, {:status, initial})

      # Send update
      update = %{"level" => 11}
      send(GameState, {:event, :gmcp_status, update})

      Process.sleep(10)

      # Should merge
      result = GameState.get(:status)
      assert result == %{"level" => 11, "class" => "Warrior"}
    end

    test "ignores non-map GMCP data" do
      # Send invalid data
      send(GameState, {:event, :gmcp_vitals, "not a map"})

      Process.sleep(10)

      # Should not crash or update state
      result = GameState.get(:vitals)
      assert result == nil
    end

    test "ignores unknown messages" do
      send(GameState, {:unknown, :message})

      Process.sleep(10)

      # Should not crash
      assert Process.alive?(Process.whereis(GameState))
    end
  end

  describe "concurrent access" do
    test "supports concurrent reads" do
      # Insert test data
      :ets.insert(GameState, {:vitals, %{"hp" => 100}})

      # Spawn multiple processes reading concurrently
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            GameState.get(:vitals)
          end)
        end

      # All should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == %{"hp" => 100}))
    end

    test "handles concurrent updates safely" do
      # Send multiple vitals updates concurrently
      tasks =
        for hp <- 1..10 do
          Task.async(fn ->
            send(GameState, {:event, :gmcp_vitals, %{"hp" => hp}})
            Process.sleep(1)
          end)
        end

      Task.await_many(tasks)

      # Should end up with some valid value
      result = GameState.get(:vitals)
      assert is_map(result)
      assert Map.has_key?(result, "hp")
    end
  end
end
