defmodule DuetTest do
  use ExUnit.Case

  test "Duet module exists" do
    assert Code.ensure_loaded?(Duet)
  end
end
