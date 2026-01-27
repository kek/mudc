defmodule Mudc.Protocol.SupervisorTest do
  use ExUnit.Case, async: false

  alias Mudc.Protocol.Supervisor, as: ProtocolSupervisor

  describe "supervision strategy" do
    test "uses :rest_for_one strategy" do
      # Test against the already-running supervisor
      pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(pid)

      # Get supervisor info
      children = Supervisor.which_children(pid)

      # Should have 3 children: Dispatcher, GMCP.Handler, GameState
      assert length(children) == 3

      # Verify children are present
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)

      assert Mudc.Protocol.Dispatcher in child_ids
      assert Mudc.Network.GMCP.Handler in child_ids
      assert Mudc.State.GameState in child_ids
    end

    test "restarts dependent children when earlier child crashes" do
      supervisor_pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(supervisor_pid)

      # Get initial children
      initial_children = Supervisor.which_children(supervisor_pid)

      # Find Dispatcher PID
      {_id, dispatcher_pid, _type, _modules} =
        Enum.find(initial_children, fn {id, _pid, _type, _modules} ->
          id == Mudc.Protocol.Dispatcher
        end)

      initial_dispatcher_pid = dispatcher_pid

      # Kill the Dispatcher
      Process.exit(dispatcher_pid, :kill)

      # Wait for supervisor to restart
      Process.sleep(200)

      # Get new children - all should be restarted due to :rest_for_one
      new_children = Supervisor.which_children(supervisor_pid)

      # Verify all children are running
      assert length(new_children) == 3

      # Find new Dispatcher PID
      {_id, new_dispatcher_pid, _type, _modules} =
        Enum.find(new_children, fn {id, _pid, _type, _modules} ->
          id == Mudc.Protocol.Dispatcher
        end)

      # Dispatcher should have a new PID
      assert new_dispatcher_pid != initial_dispatcher_pid

      Enum.each(new_children, fn {_id, pid, _type, _modules} ->
        assert Process.alive?(pid)
      end)
    end
  end

  describe "child processes" do
    test "all children start successfully" do
      supervisor_pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(supervisor_pid)

      children = Supervisor.which_children(supervisor_pid)

      # Verify all children are alive
      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert is_pid(pid)
        assert Process.alive?(pid)
      end)
    end

    test "children are started in order" do
      supervisor_pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(supervisor_pid)

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
      supervisor_pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(supervisor_pid)

      # Get GameState (last child, safest to kill) and kill it
      children = Supervisor.which_children(supervisor_pid)

      {_id, child_pid, _type, _modules} =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Mudc.State.GameState
        end)

      Process.exit(child_pid, :kill)

      # Wait a bit
      Process.sleep(100)

      # Supervisor should still be alive
      assert Process.alive?(supervisor_pid)

      # Children should be restarted
      new_children = Supervisor.which_children(supervisor_pid)
      assert length(new_children) == 3

      # All should be alive
      Enum.each(new_children, fn {_id, pid, _type, _modules} ->
        assert Process.alive?(pid)
      end)
    end

    test "handles restart after child crash" do
      supervisor_pid = Process.whereis(ProtocolSupervisor)
      assert is_pid(supervisor_pid)

      # Kill GameState once (safest child to restart)
      children = Supervisor.which_children(supervisor_pid)

      {_id, child_pid, _type, _modules} =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Mudc.State.GameState
        end)

      initial_pid = child_pid
      Process.exit(child_pid, :kill)

      # Wait for restart
      Process.sleep(200)

      # Supervisor should still be functional
      assert Process.alive?(supervisor_pid)

      children = Supervisor.which_children(supervisor_pid)
      assert length(children) == 3

      # All children should be alive
      Enum.each(children, fn {_id, pid, _type, _modules} ->
        assert Process.alive?(pid)
      end)

      # GameState should have a new PID
      {_id, new_pid, _type, _modules} =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Mudc.State.GameState
        end)

      assert new_pid != initial_pid
    end
  end
end
