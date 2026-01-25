defmodule Mudc.Network.ConnectionTest do
  use ExUnit.Case, async: false

  alias Mudc.Network.Connection

  # Note: These tests work with the Connection that's started by the Application.
  # The Connection is configured to not auto-connect by default in test env.

  describe "status/0" do
    test "returns connection information" do
      status = Connection.status()

      assert is_map(status)
      assert Map.has_key?(status, :connected)
      assert Map.has_key?(status, :host)
      assert Map.has_key?(status, :port)
    end

    test "shows disconnected state by default" do
      status = Connection.status()
      assert status.connected == false
    end

    test "includes host and port information" do
      status = Connection.status()
      assert status.host != nil
      assert status.port != nil
    end
  end

  describe "send_command/1" do
    test "returns error when not connected" do
      # Ensure we're disconnected first
      Connection.disconnect()

      result = Connection.send_command("test")
      assert result == {:error, :not_connected}
    end

    test "accepts commands as strings" do
      # This should return error since we're not connected
      result = Connection.send_command("look")
      assert result == {:error, :not_connected}
    end
  end

  describe "disconnect/0" do
    test "succeeds even when not connected" do
      # Call disconnect multiple times - should be idempotent
      assert Connection.disconnect() == :ok
      assert Connection.disconnect() == :ok
    end

    test "updates state to disconnected" do
      Connection.disconnect()
      status = Connection.status()
      assert status.connected == false
    end
  end
end
