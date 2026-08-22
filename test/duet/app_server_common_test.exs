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

  test "build_non_interactive_answers/2 builds answers for user input requests" do
    params = %{"questions" => [%{"id" => "choice"}]}

    assert {:ok, %{"choice" => %{"answers" => ["no input"]}}} =
             AppServerCommon.build_non_interactive_answers(params, "no input")
  end

  test "start_app_server/4 marks commands with the duet entry identity" do
    port =
      AppServerCommon.start_app_server(
        "printf '%s|%s\\n' \"$CODEX_DUET_ENTRY\" \"$CODEX_DUET_ENTRY_NAME\"",
        File.cwd!(),
        1024,
        "research_player"
      )

    assert_receive {^port, {:data, {:eol, "1|research_player"}}}, 1_000
    assert_receive {^port, {:exit_status, 0}}, 1_000
  end

  test "inject_codex_shell_environment/2 configures turn shell variables" do
    command =
      AppServerCommon.inject_codex_shell_environment(
        "codex app-server --stdio",
        "work_generalist_'2"
      )

    assert OptionParser.split(command) == [
             "codex",
             "app-server",
             "-c",
             ~s(shell_environment_policy.set.CODEX_DUET_ENTRY="1"),
             "-c",
             ~s(shell_environment_policy.set.CODEX_DUET_ENTRY_NAME="work_generalist_'2"),
             "--stdio"
           ]
  end

  test "inject_codex_shell_environment/2 leaves custom app servers unchanged" do
    command = "elixir custom_app_server.exs"

    assert AppServerCommon.inject_codex_shell_environment(command, "custom") == command
  end
end
