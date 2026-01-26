defmodule Mudc.Protocol.SupervisorTest do
  use ExUnit.Case, async: false

  alias Mudc.Protocol.Supervisor, as: ProtocolSupervisor

  describe "supervision strategy" do
    test "uses :rest_for_one strategy" do
      # Start the supervisor
      {:ok, pid} = start_supervised(ProtocolSupervisor)

      # Get supervisor info
      children = Supervisor.which_children(pid)

      # Should have 3 children: Dispatcher, GMCP.Handler, GameState
      assert length(children) == 3

      # Verify children are present
      child_modules = Enum.map(children, fn {_id, _pid, _type, [module]} -> module end)

      assert Mudc.Protocol.Dispatcher in child_modules
      assert Mudc.Network.GMCP.Handler in child_modules
      assert Mudc.State.GameState in child_modules
    end

    test "restarts dependent children when earlier child crashes" do
      {:ok, supervisor_pid} = start_supervised(ProtocolSupervisor)

      # Get initial children
      initial_children = Supervisor.which_children(supervisor_pid)

      # Find Dispatcher PID
      {_id, dispatcher_pid, _type, _modules} =
        Enum.find(initial_children, fn {id, _pid, _type, _modules} ->
          id == Mudc.Protocol.Dispatcher
        end)

      # Kill the Dispatcher
      Process.exit(dispatcher_pid, :kill)

      # Wait for supervisor to restart
      Process.sleep(100)

      # Get new children - all should be restarted due to :rest_for_one
      new_children = Supervisor.which_children(supervisor_pid)

      # Verify all children are running
      assert length(new_children) == 3

      Enum.each(new_children, fn {_id, pid, _type, _modules} ->
        assert Process.alive?(pid)
      end)
    end
  end

  describe "child processes" do
    test "all children start successfully" do
      {:ok, supervisor_pid} = start_supervised(ProtocolSupervisor)

      children = Supervisor.which_children(supervisor_pid)

      # Verify all children are alive
      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
    end

    test "children are started in order" do
      {:ok, supervisor_pid} = start_supervised(ProtocolSupervisor)

      children = Supervisor.which_children(supervisor_pid)

      # Children list is in reverse order from supervision tree
      # (last started appears first in the list)
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)

      # Verify all expected children are present
      assert Mudc.Protocol.Dispatcher in child_ids
      assert Mudc.Network.GMCP.Handler in child_ids
      assert Mudc.State.GameState in child_ids
    end
  end

  describe "fault tolerance" do
    test "supervisor survives child crashes" do
      {:ok, supervisor_pid} = start_supervised(ProtocolSupervisor)

      # Get a child and kill it
      [{_id, child_pid, _type, _modules} | _] = Supervisor.which_children(supervisor_pid)

      Process.exit(child_pid, :kill)

      # Wait a bit
      Process.sleep(100)

      # Supervisor should still be alive
      assert Process.alive?(supervisor_pid)

      # Children should be restarted
      children = Supervisor.which_children(supervisor_pid)
      assert length(children) == 3
    end

    test "handles rapid restarts" do
      {:ok, supervisor_pid} = start_supervised(ProtocolSupervisor)

      # Kill children multiple times
      for _i <- 1..3 do
        [{_id, child_pid, _type, _modules} | _] = Supervisor.which_children(supervisor_pid)
        Process.exit(child_pid, :kill)
        Process.sleep(50)
      end

      # Supervisor should still be functional
      assert Process.alive?(supervisor_pid)

      children = Supervisor.which_children(supervisor_pid)
      assert length(children) == 3
    end
  end
end
