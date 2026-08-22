defmodule Duet.BridgeLogTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Duet.BridgeLog)
    :ok
  end

  test "publishes events with ordered sequences and required metadata" do
    assert {:ok, first} =
             Duet.BridgeLog.publish("work_generalist_1", "feat/bridge-log", "tests added")

    assert first.sequence == 1
    assert first.sender == "work_generalist_1"
    assert first.branch == "feat/bridge-log"
    assert first.body == "tests added"
    assert %DateTime{} = first.inserted_at

    assert {:ok, second} = Duet.BridgeLog.publish("bridge", "feat/bridge-log", "reviewed")
    assert second.sequence == 2

    assert {:ok, [^first, ^second]} = Duet.BridgeLog.read_after(0)
  end

  test "read_unread advances a per-reader cursor and omits self-published events" do
    assert {:ok, own_event} =
             Duet.BridgeLog.publish("work_generalist_1", "feat/bridge-log", "started")

    assert {:ok, other_event} =
             Duet.BridgeLog.publish("work_generalist_2", "feat/bridge-log", "tests are green")

    assert {:ok, [^other_event]} = Duet.BridgeLog.read_unread("work_generalist_1")
    assert {:ok, []} = Duet.BridgeLog.read_unread("work_generalist_1")

    assert {:ok, later_own_event} =
             Duet.BridgeLog.publish("work_generalist_1", "feat/bridge-log", "implementation done")

    assert later_own_event.sequence > own_event.sequence
    assert {:ok, []} = Duet.BridgeLog.read_unread("work_generalist_1")

    assert {:ok, later_other_event} =
             Duet.BridgeLog.publish("work_generalist_2", "feat/bridge-log", "verified")

    assert {:ok, [^later_other_event]} = Duet.BridgeLog.read_unread("work_generalist_1")
  end

  test "read_after does not advance a reader cursor" do
    assert {:ok, event} =
             Duet.BridgeLog.publish("work_generalist_2", "feat/bridge-log", "result")

    assert {:ok, [^event]} = Duet.BridgeLog.read_after(0)
    assert {:ok, [^event]} = Duet.BridgeLog.read_unread("work_generalist_1")
  end

  test "reset clears events and cursors and restarts sequencing" do
    assert {:ok, _event} = Duet.BridgeLog.publish("bridge", "feat/bridge-log", "before reset")
    assert {:ok, [_event]} = Duet.BridgeLog.read_unread("work_generalist_1")

    assert :ok = Duet.BridgeLog.reset()
    assert {:ok, []} = Duet.BridgeLog.read_after(0)
    assert {:ok, []} = Duet.BridgeLog.read_unread("work_generalist_1")

    assert {:ok, event} = Duet.BridgeLog.publish("bridge", "feat/bridge-log", "after reset")
    assert event.sequence == 1
  end

  test "rejects missing event metadata and invalid reads" do
    assert {:error, :invalid_sender} = Duet.BridgeLog.publish(" ", "main", "body")
    assert {:error, :invalid_branch} = Duet.BridgeLog.publish("bridge", " ", "body")
    assert {:error, :invalid_body} = Duet.BridgeLog.publish("bridge", "main", " ")
    assert {:error, :invalid_event} = Duet.BridgeLog.publish(:bridge, "main", "body")
    assert {:error, :invalid_reader} = Duet.BridgeLog.read_unread("")
    assert {:error, :invalid_sequence} = Duet.BridgeLog.read_after(-1)
  end

  test "serializes concurrent publishes" do
    events =
      1..20
      |> Task.async_stream(
        fn number ->
          Duet.BridgeLog.publish("entry-#{number}", "feat/bridge-log", "event #{number}")
        end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, event}} -> event end)

    assert events |> Enum.map(& &1.sequence) |> Enum.sort() == Enum.to_list(1..20)
  end
end
