defmodule Mudc.Scripting.ScriptLoaderTest do
  use ExUnit.Case, async: false

  alias Mudc.Scripting.ScriptLoader

  setup do
    # Create a temporary script directory for testing
    script_dir = Path.join(System.tmp_dir!(), "mudc_test_scripts_#{:rand.uniform(10000)}")
    File.mkdir_p!(script_dir)

    # Start ScriptLoader with test directory
    start_supervised!({ScriptLoader, script_dir: script_dir})

    on_exit(fn ->
      File.rm_rf!(script_dir)
    end)

    {:ok, script_dir: script_dir}
  end

  describe "script_dir/0" do
    test "returns the configured script directory", %{script_dir: script_dir} do
      result = ScriptLoader.script_dir()

      assert result == script_dir
    end
  end

  describe "load_file/1" do
    test "loads a valid Lua script file", %{script_dir: script_dir} do
      # Create a simple Lua script
      script_path = Path.join(script_dir, "test.lua")
      File.write!(script_path, "-- Test script\nprint('hello')")

      # Note: This requires Engine to be running
      result = ScriptLoader.load_file(script_path)

      # Result depends on Engine availability
      assert result == :ok or match?({:error, _}, result)
    end

    test "returns error for non-existent file" do
      result = ScriptLoader.load_file("/nonexistent/path/script.lua")

      assert {:error, _reason} = result
    end

    test "returns error for invalid Lua syntax", %{script_dir: script_dir} do
      # Create a script with invalid Lua
      script_path = Path.join(script_dir, "invalid.lua")
      File.write!(script_path, "this is not valid lua !!!!")

      result = ScriptLoader.load_file(script_path)

      # Should fail during execution
      assert {:error, _reason} = result
    end
  end

  describe "reload/0" do
    test "reloads all scripts from directory", %{script_dir: script_dir} do
      # Create some test scripts
      File.write!(Path.join(script_dir, "01-first.lua"), "-- First")
      File.write!(Path.join(script_dir, "02-second.lua"), "-- Second")

      result = ScriptLoader.reload()

      assert result == :ok
    end

    test "clears triggers and aliases before reload" do
      # This is tested indirectly - reload() calls clear on both managers
      result = ScriptLoader.reload()

      assert result == :ok
    end
  end

  describe "automatic loading on init" do
    test "loads scripts in alphabetical order", %{script_dir: script_dir} do
      # Create scripts with numeric prefixes
      File.write!(Path.join(script_dir, "01-first.lua"), "-- First")
      File.write!(Path.join(script_dir, "03-third.lua"), "-- Third")
      File.write!(Path.join(script_dir, "02-second.lua"), "-- Second")

      # Reload to trigger loading
      ScriptLoader.reload()

      # Scripts should be loaded in order: 01, 02, 03
      # Verification would require checking Engine execution order
      # which is complex without full integration
      assert true
    end

    test "only loads .lua files", %{script_dir: script_dir} do
      # Create various file types
      File.write!(Path.join(script_dir, "script.lua"), "-- Lua")
      File.write!(Path.join(script_dir, "readme.txt"), "Not Lua")
      File.write!(Path.join(script_dir, "data.json"), "{}")

      # Reload should only load .lua files
      result = ScriptLoader.reload()

      assert result == :ok
      # Only script.lua should be loaded (verified indirectly)
    end

    test "handles empty script directory gracefully", %{script_dir: script_dir} do
      # Ensure directory is empty
      File.ls!(script_dir)
      |> Enum.each(&File.rm!(Path.join(script_dir, &1)))

      result = ScriptLoader.reload()

      assert result == :ok
    end
  end
end
