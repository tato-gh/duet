defmodule Duet.ErpcChannelTest do
  use ExUnit.Case

  setup do
    registry = start_supervised!({Registry, keys: :unique, name: Duet.ErpcChannel.Registry})
    {:ok, registry: registry}
  end

  test "post/2 returns {:error, :not_found} when entry is not registered" do
    assert {:error, :not_found} = Duet.ErpcChannel.post("nonexistent", "hello")
  end

  test "post/2 returns {:error, :not_found} for any unregistered name" do
    assert {:error, :not_found} = Duet.ErpcChannel.post("review", "prompt")
    assert {:error, :not_found} = Duet.ErpcChannel.post("summary", "prompt")
  end
end
