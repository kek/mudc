defmodule Mudc.Network.GMCP.HandlerTest do
  use ExUnit.Case, async: false

  alias Mudc.Network.GMCP.Handler
  alias Mudc.Events.Bus

  setup do
    # Start required dependencies
    start_supervised!(Mudc.State.GameState)
    start_supervised!(Handler)

    # Subscribe to GMCP events
    Bus.subscribe(:gmcp)

    on_exit(fn ->
      Bus.unsubscribe(:gmcp)
    end)

    :ok
  end

  describe "process_gmcp/2" do
    test "processes char.vitals and publishes event" do
      json = ~s({"hp": 120, "max_hp": 150, "mana": 80, "max_mana": 100})

      Handler.process_gmcp("char.vitals", json)

      # Should receive vitals event
      assert_receive {:event, :gmcp, {:vitals, vitals}}, 500

      assert vitals.hp == 120
      assert vitals.max_hp == 150
      assert vitals.mana == 80
      assert vitals.max_mana == 100
    end

    test "processes room.info and publishes event" do
      json = ~s({"name": "Market Square", "area": "Bree"})

      Handler.process_gmcp("room.info", json)

      # Should receive room event
      assert_receive {:event, :gmcp, {:room, room}}, 500

      assert room.name == "Market Square"
      assert room.area == "Bree"
    end

    test "handles unknown GMCP modules" do
      json = ~s({"data": "test"})

      Handler.process_gmcp("unknown.module", json)

      # Should receive generic GMCP event
      assert_receive {:event, :gmcp, {:gmcp, "unknown.module", data}}, 500

      assert data["data"] == "test"
    end

    test "handles invalid JSON gracefully" do
      invalid_json = "{invalid json"

      # Should not crash, just log error
      Handler.process_gmcp("char.vitals", invalid_json)

      # Should not receive any event
      refute_receive {:event, :gmcp, _}, 200
    end

    test "handles missing fields in vitals" do
      json = ~s({"hp": 100})  # Missing other fields

      Handler.process_gmcp("char.vitals", json)

      # Should still publish event with available data
      assert_receive {:event, :gmcp, {:vitals, vitals}}, 500

      assert vitals.hp == 100
      # Other fields may be nil or have defaults
    end
  end

  describe "send_gmcp/2" do
    test "formats GMCP message correctly" do
      # This would require a connection to test properly
      # We can verify the function exists and accepts parameters
      assert function_exported?(Handler, :send_gmcp, 2)
    end
  end

  describe "GMCP module routing" do
    test "routes char.status correctly" do
      json = ~s({"level": 10, "class": "Warrior"})

      Handler.process_gmcp("char.status", json)

      # Should receive appropriate event
      assert_receive {:event, :gmcp, _}, 500
    end

    test "routes comm.channel correctly" do
      json = ~s({"channel": "gossip", "player": "Alice", "message": "Hello"})

      Handler.process_gmcp("comm.channel", json)

      # Should receive channel event
      assert_receive {:event, :gmcp, _}, 500
    end
  end

  describe "GameState integration" do
    test "updates GameState with room info" do
      json = ~s({"name": "Forest", "area": "Shire"})

      Handler.process_gmcp("room.info", json)

      # Wait for processing
      Process.sleep(50)

      # GameState should be updated
      room = Mudc.State.GameState.get_room()
      assert room.name == "Forest"
      assert room.area == "Shire"
    end

    test "updates GameState with vitals" do
      json = ~s({"hp": 150, "max_hp": 150})

      Handler.process_gmcp("char.vitals", json)

      # Wait for processing
      Process.sleep(50)

      # GameState should be updated
      vitals = Mudc.State.GameState.get_vitals()
      assert vitals.hp == 150
      assert vitals.max_hp == 150
    end
  end

  describe "error handling" do
    test "handles empty JSON" do
      Handler.process_gmcp("char.vitals", "")

      # Should not crash
      refute_receive {:event, :gmcp, _}, 200
    end

    test "handles null values in JSON" do
      json = ~s({"hp": null, "max_hp": 150})

      Handler.process_gmcp("char.vitals", json)

      # Should handle gracefully
      assert_receive {:event, :gmcp, {:vitals, _vitals}}, 500
    end

    test "handles very large numbers" do
      json = ~s({"hp": 999999999, "max_hp": 999999999})

      Handler.process_gmcp("char.vitals", json)

      assert_receive {:event, :gmcp, {:vitals, vitals}}, 500
      assert vitals.hp == 999999999
    end
  end
end
