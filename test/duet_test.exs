defmodule DuetTest do
  use ExUnit.Case
  doctest Duet

  test "greets the world" do
    assert Duet.hello() == :world
  end
end
