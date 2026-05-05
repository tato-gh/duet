defmodule Duet.EntryTest do
  use ExUnit.Case

  setup do
    start_supervised!({Registry, keys: :unique, name: Duet.EntryRegistry})

    tmp_dir =
      Path.join(System.tmp_dir!(), "duet-entry-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    config_path = Path.join(tmp_dir, "DUET.md")
    File.write!(config_path, "---\nentries: []\n---\n")
    Duet.Config.set_config_file(config_path)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  test "/compact summarizes the old thread and hands the summary to a new thread", %{
    tmp_dir: tmp_dir
  } do
    log_path = Path.join(tmp_dir, "app_server.log")
    File.write!(log_path, "")

    start_entry!(
      name: "compact-success",
      role: "レビュー担当",
      command: fake_app_server_command(log_path)
    )

    assert {:ok, "引き継ぎを確認しました"} = Duet.post("compact-success", "/compact")

    received = read_received_messages(log_path)
    turn_starts = Enum.filter(received, &(Map.get(&1, "method") == "turn/start"))

    assert length(turn_starts) == 2

    [summary_turn, handoff_turn] = turn_starts
    assert get_in(summary_turn, ["params", "threadId"]) == "thread-1"

    assert summary_turn
           |> input_text()
           |> String.contains?("引き継ぎメモを作成してください")

    assert get_in(handoff_turn, ["params", "threadId"]) == "thread-2"

    handoff_text = input_text(handoff_turn)
    assert String.contains?(handoff_text, "あなたのroleはレビュー担当です。")
    assert String.contains?(handoff_text, "前スレッドからの引き継ぎ情報です")
    assert String.contains?(handoff_text, "<handoff>\n引き継ぎ要約\n</handoff>")
    assert String.contains?(handoff_text, "ユーザーからの新しい作業依頼ではなく")
  end

  test "/compact returns an error when the summary is empty", %{tmp_dir: tmp_dir} do
    log_path = Path.join(tmp_dir, "app_server.log")
    File.write!(log_path, "")

    start_entry!(
      name: "compact-empty",
      command: fake_app_server_command(log_path, summary: "   ")
    )

    assert {:error, :empty_compact_summary} = Duet.post("compact-empty", "/compact")

    received = read_received_messages(log_path)
    thread_starts = Enum.filter(received, &(Map.get(&1, "method") == "thread/start"))
    turn_starts = Enum.filter(received, &(Map.get(&1, "method") == "turn/start"))

    assert length(thread_starts) == 1
    assert length(turn_starts) == 1
  end

  defp start_entry!(opts) do
    config = %{
      name: Keyword.fetch!(opts, :name),
      command: Keyword.fetch!(opts, :command),
      role: Keyword.get(opts, :role, ""),
      approval_policy: "never",
      thread_sandbox: "read-only",
      turn_sandbox_policy: %{"type" => "readOnly", "networkAccess" => false}
    }

    start_supervised!({Duet.Entry, config})
    wait_until_idle(config.name)
  end

  defp wait_until_idle(name) do
    registered_name = {:via, Registry, {Duet.EntryRegistry, name}}

    case :sys.get_state(registered_name).status do
      :idle ->
        :ok

      _status ->
        Process.sleep(10)
        wait_until_idle(name)
    end
  end

  defp fake_app_server_command(log_path, opts \\ []) do
    script_path = Path.expand("../support/fake_app_server.script", __DIR__)
    summary = Keyword.get(opts, :summary, "引き継ぎ要約")

    [
      "FAKE_APP_SERVER_LOG=#{shell_escape(log_path)}",
      "FAKE_COMPACT_SUMMARY=#{shell_escape(summary)}",
      "elixir #{shell_escape(script_path)}"
    ]
    |> Enum.join(" ")
  end

  defp read_received_messages(log_path) do
    log_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
    |> Enum.map(&Map.fetch!(&1, "received"))
  end

  defp input_text(message) do
    message
    |> get_in(["params", "input"])
    |> List.first(%{})
    |> Map.get("text", "")
  end

  defp shell_escape(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
