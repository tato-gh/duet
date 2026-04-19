defmodule Duet.AppServerCommonTest do
  use ExUnit.Case, async: true

  alias Duet.AppServerCommon

  test "decode_and_process/4 decodes valid UTF-8 JSON lines" do
    line = ~s|{"method":"echo","params":{"text":"依頼内容"}}|

    state =
      AppServerCommon.decode_and_process(
        line,
        %{seen: nil},
        fn msg, st ->
          %{st | seen: msg}
        end,
        "[test]"
      )

    assert get_in(state, [:seen, "params", "text"]) == "依頼内容"
  end

  test "decode_and_process/4 normalizes invalid UTF-8 latin1 bytes before JSON decode" do
    latin1_json =
      [~s|{"method":"echo","params":{"text":"|, <<0xE9>>, ~s|"}}|] |> IO.iodata_to_binary()

    state =
      AppServerCommon.decode_and_process(
        latin1_json,
        %{seen: nil},
        fn msg, st ->
          %{st | seen: msg}
        end,
        "[test]"
      )

    assert get_in(state, [:seen, "params", "text"]) == "é"
  end
end
