defmodule MudcTest do
  use ExUnit.Case
  doctest Mudc

  test "greets the world" do
    assert Mudc.hello() == :world
  end
end
