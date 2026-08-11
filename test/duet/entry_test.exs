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
      model: "gpt-5.6-luna",
      reasoning_effort: "high",
      service_tier: "fast",
      command: fake_app_server_command(log_path)
    )

    assert {:ok, "引き継ぎを確認しました"} = Duet.post("compact-success", "/compact")

    received = read_received_messages(log_path)
    thread_starts = Enum.filter(received, &(Map.get(&1, "method") == "thread/start"))
    turn_starts = Enum.filter(received, &(Map.get(&1, "method") == "turn/start"))

    assert length(thread_starts) == 2
    assert Enum.all?(thread_starts, &(get_in(&1, ["params", "model"]) == "gpt-5.6-luna"))
    assert Enum.all?(thread_starts, &(get_in(&1, ["params", "serviceTier"]) == "fast"))
    assert length(turn_starts) == 2
    assert Enum.all?(turn_starts, &(get_in(&1, ["params", "effort"]) == "high"))

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

  test "/clear applies the entry service tier to the new thread", %{tmp_dir: tmp_dir} do
    log_path = Path.join(tmp_dir, "app_server.log")
    File.write!(log_path, "")

    start_entry!(
      name: "clear-fast",
      service_tier: "fast",
      command: fake_app_server_command(log_path)
    )

    assert {:ok, ""} = Duet.post("clear-fast", "/clear")

    received = read_received_messages(log_path)
    thread_starts = Enum.filter(received, &(Map.get(&1, "method") == "thread/start"))

    assert length(thread_starts) == 2
    assert Enum.all?(thread_starts, &(get_in(&1, ["params", "serviceTier"]) == "fast"))
  end

  test "post_all returns busy and cast_all reserves a queued prompt", %{
    tmp_dir: tmp_dir
  } do
    log_path = Path.join(tmp_dir, "app_server.log")
    File.write!(log_path, "")

    start_entry!(
      name: "broadcast",
      command: fake_app_server_command(log_path, turn_delay_ms: 200)
    )

    first_post = Task.async(fn -> Duet.post("broadcast", "first prompt") end)
    wait_until_status("broadcast", :waiting)

    assert {:ok, ["broadcast"]} = Duet.cast_all("branch changed")
    assert {:error, :busy} = Duet.post("broadcast", "direct prompt")

    assert [{"broadcast", {:error, :busy}}] = Duet.post_all("busy prompt")

    assert {:ok, "引き継ぎを確認しました"} = Task.await(first_post)
    wait_until_idle("broadcast")

    received = read_received_messages(log_path)

    turn_inputs =
      received
      |> Enum.filter(&(Map.get(&1, "method") == "turn/start"))
      |> Enum.map(&input_text/1)

    assert Enum.any?(turn_inputs, &String.contains?(&1, "first prompt"))
    assert Enum.any?(turn_inputs, &String.contains?(&1, "branch changed"))
    refute Enum.any?(turn_inputs, &String.contains?(&1, "busy prompt"))
  end

  test "post_all waits for every running entry", %{tmp_dir: tmp_dir} do
    alpha_log_path = Path.join(tmp_dir, "alpha.log")
    beta_log_path = Path.join(tmp_dir, "beta.log")
    File.write!(alpha_log_path, "")
    File.write!(beta_log_path, "")

    start_entry!(name: "beta", command: fake_app_server_command(beta_log_path))
    start_entry!(name: "alpha", command: fake_app_server_command(alpha_log_path))

    assert [
             {"alpha", {:ok, "引き継ぎを確認しました"}},
             {"beta", {:ok, "引き継ぎを確認しました"}}
           ] = Duet.post_all("shared prompt")

    assert alpha_log_path
           |> read_received_messages()
           |> Enum.filter(&(Map.get(&1, "method") == "turn/start"))
           |> Enum.any?(&(input_text(&1) |> String.contains?("shared prompt")))

    assert beta_log_path
           |> read_received_messages()
           |> Enum.filter(&(Map.get(&1, "method") == "turn/start"))
           |> Enum.any?(&(input_text(&1) |> String.contains?("shared prompt")))
  end

  test "overview asks an entry to describe its current context", %{tmp_dir: tmp_dir} do
    log_path = Path.join(tmp_dir, "overview.log")
    File.write!(log_path, "")

    start_entry!(
      name: "api-1",
      role: "API 担当者",
      command: fake_app_server_command(log_path)
    )

    assert {:ok, "引き継ぎを確認しました"} = Duet.overview("api-1")

    assert [{"api-1", {:ok, "引き継ぎを確認しました"}}] = Duet.overview_all()

    turn_inputs =
      log_path
      |> read_received_messages()
      |> Enum.filter(&(Map.get(&1, "method") == "turn/start"))
      |> Enum.map(&input_text/1)

    assert Enum.all?(turn_inputs, &String.contains?(&1, "この entry の overview"))
    assert Enum.all?(turn_inputs, &String.contains?(&1, "確認できる事実だけを、最大 3 項目・各 1 文"))
    assert Enum.all?(turn_inputs, &String.contains?(&1, "未完了の事項が明確にあるかどうか"))
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
      model: Keyword.get(opts, :model),
      reasoning_effort: Keyword.get(opts, :reasoning_effort),
      service_tier: Keyword.get(opts, :service_tier),
      approval_policy: "never",
      thread_sandbox: "read-only",
      turn_sandbox_policy: %{"type" => "readOnly", "networkAccess" => false}
    }

    start_supervised!({Duet.Entry, config})
    wait_until_idle(config.name)
  end

  defp wait_until_idle(name) do
    wait_until_status(name, :idle)
  end

  defp wait_until_status(name, expected_status) do
    registered_name = {:via, Registry, {Duet.EntryRegistry, name}}

    case :sys.get_state(registered_name).status do
      ^expected_status ->
        :ok

      _status ->
        Process.sleep(10)
        wait_until_status(name, expected_status)
    end
  end

  defp fake_app_server_command(log_path, opts \\ []) do
    script_path = Path.expand("../support/fake_app_server.script", __DIR__)
    summary = Keyword.get(opts, :summary, "引き継ぎ要約")
    turn_delay_ms = Keyword.get(opts, :turn_delay_ms, 0)

    [
      "FAKE_APP_SERVER_LOG=#{shell_escape(log_path)}",
      "FAKE_COMPACT_SUMMARY=#{shell_escape(summary)}",
      "FAKE_TURN_DELAY_MS=#{turn_delay_ms}",
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
