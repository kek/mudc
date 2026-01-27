defmodule Mudc.Network.GMCP.HandlerTest do
  use ExUnit.Case, async: false

  alias Mudc.Network.GMCP.Handler
  alias Mudc.Network.GMCP.Parser
  alias Mudc.Events.Bus

  setup do
    # GameState and Handler are already started by the application supervisor
    # Reset GMCP state by simulating server rejection
    if Handler.enabled?() do
      Handler.handle_negotiation({:wont, 201})
    end

    # Just subscribe to GMCP events
    Bus.subscribe(:gmcp)
    Bus.subscribe(:gmcp_vitals)
    Bus.subscribe(:gmcp_room)

    on_exit(fn ->
      Bus.unsubscribe(:gmcp)
      Bus.unsubscribe(:gmcp_vitals)
      Bus.unsubscribe(:gmcp_room)
    end)

    :ok
  end

  describe "handle_subneg/1" do
    test "processes char.vitals and publishes event" do
      data = Parser.encode("Char.Vitals", %{"hp" => 120, "maxhp" => 150})

      Handler.handle_subneg(data)

      # Should receive vitals event
      assert_receive {:event, :gmcp_vitals, vitals}, 500

      assert vitals["hp"] == 120
      assert vitals["maxhp"] == 150
    end

    test "processes room.info and publishes event" do
      data = Parser.encode("Room.Info", %{"name" => "Market Square", "area" => "Bree"})

      Handler.handle_subneg(data)

      # Should receive room event
      assert_receive {:event, :gmcp_room, room}, 500

      assert room["name"] == "Market Square"
      assert room["area"] == "Bree"
    end

    test "handles unknown GMCP modules" do
      data = Parser.encode("Unknown.Module", %{"data" => "test"})

      Handler.handle_subneg(data)

      # Should receive generic GMCP event
      assert_receive {:event, :gmcp, {:message, "Unknown.Module", payload}}, 500

      assert payload["data"] == "test"
    end

    test "handles malformed data gracefully" do
      # Send invalid data
      Handler.handle_subneg("invalid data that can't be parsed")

      # Should not crash, just not send events
      refute_receive {:event, :gmcp, _}, 200
      refute_receive {:event, :gmcp_vitals, _}, 200
    end
  end

  describe "send_message/2" do
    test "returns error when GMCP not enabled" do
      # Handler starts with GMCP disabled
      result = Handler.send_message("Core.Hello", %{"client" => "Mudc"})

      assert result == {:error, :gmcp_not_enabled}
    end
  end

  describe "enabled?/0" do
    test "returns false by default" do
      result = Handler.enabled?()

      assert result == false
    end
  end

  describe "handle_negotiation/1" do
    test "enables GMCP when server offers it" do
      result = Handler.handle_negotiation({:will, 201})

      assert {:ok, _response} = result
      assert Handler.enabled?() == true
    end

    test "disables GMCP when server rejects it" do
      # First enable it
      Handler.handle_negotiation({:will, 201})

      # Then disable
      result = Handler.handle_negotiation({:wont, 201})

      assert result == :ok
      assert Handler.enabled?() == false
    end
  end

  describe "GameState integration" do
    test "updates GameState with room info" do
      data = Parser.encode("Room.Info", %{"name" => "Forest", "area" => "Shire"})

      Handler.handle_subneg(data)

      # Wait for async processing
      Process.sleep(50)

      # GameState should be updated
      room = Mudc.State.GameState.room()
      assert room["name"] == "Forest"
      assert room["area"] == "Shire"
    end

    test "updates GameState with vitals" do
      data = Parser.encode("Char.Vitals", %{"hp" => 150, "maxhp" => 150})

      Handler.handle_subneg(data)

      # Wait for async processing
      Process.sleep(50)

      # GameState should be updated
      vitals = Mudc.State.GameState.vitals()
      assert vitals["hp"] == 150
      assert vitals["maxhp"] == 150
    end
  end

  describe "event publishing" do
    test "publishes Char.Status to gmcp_status topic" do
      Bus.subscribe(:gmcp_status)

      data = Parser.encode("Char.Status", %{"level" => 10, "class" => "Warrior"})

      Handler.handle_subneg(data)

      assert_receive {:event, :gmcp_status, status}, 500
      assert status["level"] == 10
      assert status["class"] == "Warrior"

      Bus.unsubscribe(:gmcp_status)
    end

    test "publishes Comm.Channel to gmcp_channel topic" do
      Bus.subscribe(:gmcp_channel)

      data =
        Parser.encode("Comm.Channel", %{
          "channel" => "gossip",
          "player" => "Alice",
          "message" => "Hello"
        })

      Handler.handle_subneg(data)

      assert_receive {:event, :gmcp_channel, channel}, 500
      assert channel["channel"] == "gossip"
      assert channel["player"] == "Alice"

      Bus.unsubscribe(:gmcp_channel)
    end
  end
end
