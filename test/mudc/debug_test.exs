defmodule Mudc.DebugTest do
  use ExUnit.Case, async: false

  alias Mudc.UI.LogBuffer
  alias Mudc.Debug

  setup do
    # Clear logs before each test
    LogBuffer.clear()
    :ok
  end

  describe "LogBuffer" do
    test "stores and retrieves logs" do
      LogBuffer.add_log(:info, "Test message 1")
      LogBuffer.add_log(:error, "Test error")
      LogBuffer.add_log(:info, "Test message 2")

      logs = LogBuffer.get_logs()
      assert length(logs) == 3
      assert Enum.any?(logs, &String.contains?(&1, "Test message 1"))
      assert Enum.any?(logs, &String.contains?(&1, "Test error"))
    end

    test "filters logs by level" do
      LogBuffer.add_log(:info, "Info message")
      LogBuffer.add_log(:error, "Error message")
      LogBuffer.add_log(:warning, "Warning message")

      errors = LogBuffer.filter_by_level(:error)
      assert length(errors) == 1
      assert Enum.all?(errors, &String.contains?(&1, "[error]"))

      warnings = LogBuffer.filter_by_level(:warning)
      assert length(warnings) == 1
      assert Enum.all?(warnings, &String.contains?(&1, "[warning]"))
    end

    test "recent/1 returns last N logs" do
      for i <- 1..10 do
        LogBuffer.add_log(:info, "Message #{i}")
      end

      recent = LogBuffer.recent(5)
      assert length(recent) == 5
    end

    test "errors/0 returns only error logs" do
      LogBuffer.add_log(:info, "Info message")
      LogBuffer.add_log(:error, "Error 1")
      LogBuffer.add_log(:error, "Error 2")
      LogBuffer.add_log(:warning, "Warning")

      errors = LogBuffer.errors()
      assert length(errors) == 2
      assert Enum.all?(errors, &String.contains?(&1, "[error]"))
    end

    test "warnings/0 returns only warning logs" do
      LogBuffer.add_log(:info, "Info message")
      LogBuffer.add_log(:warning, "Warning 1")
      LogBuffer.add_log(:error, "Error")
      LogBuffer.add_log(:warning, "Warning 2")

      warnings = LogBuffer.warnings()
      assert length(warnings) == 2
      assert Enum.all?(warnings, &String.contains?(&1, "[warning]"))
    end

    test "search/1 finds logs containing pattern (case-insensitive)" do
      LogBuffer.add_log(:info, "Connection established")
      LogBuffer.add_log(:error, "Connection failed")
      LogBuffer.add_log(:info, "Disconnected")

      results = LogBuffer.search("connection")
      assert length(results) == 2
      assert Enum.all?(results, &String.contains?(String.downcase(&1), "connection"))

      results = LogBuffer.search("FAILED")
      assert length(results) == 1
    end

    test "clear/0 removes all logs" do
      LogBuffer.add_log(:info, "Message 1")
      LogBuffer.add_log(:info, "Message 2")

      assert length(LogBuffer.get_logs()) == 2

      LogBuffer.clear()
      assert LogBuffer.get_logs() == []
    end

    test "respects max lines limit" do
      # Add more than max_lines (500)
      for i <- 1..600 do
        LogBuffer.add_log(:info, "Message #{i}")
      end

      logs = LogBuffer.get_logs()
      assert length(logs) <= 500
    end
  end

  describe "Mudc.Debug" do
    test "status/0 returns ok" do
      assert Debug.status() == :ok
    end

    test "health_check/0 returns ok" do
      assert Debug.health_check() == :ok
    end

    test "logs/1 returns recent logs" do
      LogBuffer.add_log(:info, "Test log")
      logs = Debug.logs(10)
      assert is_list(logs)
    end

    test "errors/0 returns error logs" do
      LogBuffer.add_log(:error, "Test error")
      LogBuffer.add_log(:info, "Test info")

      errors = Debug.errors()
      assert is_list(errors)
      assert Enum.all?(errors, &String.contains?(&1, "[error]"))
    end

    test "warnings/0 returns warning logs" do
      LogBuffer.add_log(:warning, "Test warning")
      LogBuffer.add_log(:info, "Test info")

      warnings = Debug.warnings()
      assert is_list(warnings)
      assert Enum.all?(warnings, &String.contains?(&1, "[warning]"))
    end

    test "search_logs/1 searches log buffer" do
      LogBuffer.add_log(:info, "Test message with keyword")
      LogBuffer.add_log(:info, "Another message")

      results = Debug.search_logs("keyword")
      assert is_list(results)
      assert Enum.any?(results, &String.contains?(&1, "keyword"))
    end

    test "memory/0 returns ok" do
      assert Debug.memory() == :ok
    end

    test "memory_mb/0 returns a number" do
      mb = Debug.memory_mb()
      assert is_float(mb)
      assert mb > 0
    end

    test "processes/0 returns list of children" do
      children = Debug.processes()
      assert is_list(children)
    end

    test "game_state/0 returns map with vitals and room" do
      state = Debug.game_state()
      assert is_map(state)
      assert Map.has_key?(state, :vitals)
      assert Map.has_key?(state, :room)
    end

    test "uptime/0 returns string" do
      uptime = Debug.uptime()
      assert is_binary(uptime)
    end

    test "config/0 returns keyword list" do
      config = Debug.config()
      assert is_list(config)
    end

    test "connection_status/0 returns status" do
      status = Debug.connection_status()
      assert is_map(status) or status in [:connected, :disconnected]
    end

    test "dump/0 returns ok" do
      assert Debug.dump() == :ok
    end
  end
end
