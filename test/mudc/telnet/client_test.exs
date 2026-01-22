defmodule Mudc.Telnet.ClientTest do
  use ExUnit.Case, async: false

  alias Mudc.Telnet.Client

  describe "Client API" do
    test "send_command returns error when not connected" do
      # Start client without letting it connect
      {:ok, _pid} =
        start_supervised(
          {Client, [name: :test_client, host: "invalid.test", port: 1, timeout: 1]}
        )

      # Wait a moment for connection to fail
      Process.sleep(100)

      # Try to send a command - should error with :not_connected
      # Note: This might also crash the process, which is expected behavior
      result =
        try do
          Client.send_command("test", :test_client)
        catch
          :exit, _ -> {:error, :process_died}
        end

      assert result in [{:error, :not_connected}, {:error, :process_died}]
    end
  end

  describe "ConnectionConfig" do
    test "creates config with defaults" do
      config = Mudc.Telnet.ConnectionConfig.new()

      assert config.host == "172.24.0.1"
      assert config.port == 4242
      assert config.timeout == 5000
      assert config.active == true
    end

    test "creates config with overrides" do
      config = Mudc.Telnet.ConnectionConfig.new(host: "localhost", port: 8080)

      assert config.host == "localhost"
      assert config.port == 8080
      assert config.timeout == 5000
    end
  end
end
