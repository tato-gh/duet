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

  test "statuses keeps failed configured entries visible without changing entries" do
    entry = %{name: "broken", role: "reviewer", backend: :claude}
    Registry.put_meta(Duet.EntryRegistry, :configured_entries, [entry])
    Duet.record_entry_failure("broken", {:initialize_failed, "authentication failed"})

    assert [] = Duet.entries()
    assert [status] = Duet.statuses()
    assert status.name == "broken"
    assert status.backend == :claude
    assert status.status == :failed
    assert status.reason == {:initialize_failed, "authentication failed"}
  end
end
