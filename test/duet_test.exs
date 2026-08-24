defmodule DuetTest do
  use ExUnit.Case

  setup do
    start_supervised!({Registry, keys: :unique, name: Duet.EntryRegistry})
    :ok
  end

  test "post/2 returns {:error, :not_found} when entry is not registered" do
    assert {:error, :not_found} = Duet.post("nonexistent", "hello")
  end

  test "interrupt/1 returns {:error, :not_found} when entry is not registered" do
    assert {:error, :not_found} = Duet.interrupt("nonexistent")
  end

  test "entries/0 returns an empty list without registered entries" do
    assert [] = Duet.entries()
  end
end
