defmodule Duet.AgyEntryTest do
  use ExUnit.Case

  setup do
    start_supervised!({Registry, keys: :unique, name: Duet.EntryRegistry})
    dir = Path.join(System.tmp_dir!(), "duet-agy-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "DUET.md")
    Duet.Config.set_config_file(path)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, path: path}
  end

  test "configured agy entries retain independent sessions and use the shared API", ctx do
    {log, reviewer} =
      config(ctx, "reviewer", role: "レビュー担当", model: "test'model", reasoning_effort: "high")

    {_other_log, other} = config(ctx, "other")
    start_entry(reviewer)
    start_entry(other)

    assert {:ok, first} = Duet.post("reviewer", "こんにちは")
    assert first =~ "あなたのroleはレビュー担当です。"
    assert {:ok, second} = Duet.post("reviewer", "続き")
    assert second == first <> "\n続き"

    assert [{"other", {:ok, "broadcast"}}, {"reviewer", {:ok, "続き\nbroadcast"}}] =
             Duet.post_all("broadcast")

    assert {:ok, ["other", "reviewer"]} = Duet.cast_all("reserved")
    wait_for(fn -> Enum.all?(Duet.statuses(), &(&1.status == :ready)) end)
    assert {:ok, "reserved\ncheck"} = Duet.post("reviewer", "check")

    assert [%{"args" => args, "entry" => "reviewer"} | prompts] = records(log)
    assert Enum.count(prompts, &Map.has_key?(&1, "args")) == 0

    assert args == [
             "--input-format",
             "stream-json",
             "--output-format",
             "stream-json",
             "--mode",
             "plan",
             "--model",
             "test'model",
             "--effort",
             "high"
           ]
  end

  test "unsupported slash commands are rejected without reaching agy", ctx do
    {log, config} = config(ctx, "reviewer")
    pid = start_entry(config)

    assert {:error, :unsupported_slash_command} = Duet.post("reviewer", "/model x")
    assert {:error, :unsupported_slash_command} = Duet.post("reviewer", "  /help")
    assert {:ok, []} = Duet.cast_all("/plan")
    assert {:ok, "next"} = Duet.post("reviewer", "next")
    assert :sys.get_state(pid).pending_posts == :queue.new()
    assert [%{"args" => _}, %{"prompt" => "next"}] = records(log)
  end

  test "clear resets context, compact carries it over, and a failed turn keeps the session",
       ctx do
    {log, config} = config(ctx, "reviewer", role: "reviewer")
    start_entry(config)

    assert {:ok, _} = Duet.post("reviewer", "old context")
    assert {:error, {:agy_error, "model failed"}} = Duet.post("reviewer", "fail")
    assert {:ok, denied} = Duet.post("reviewer", "denied")
    assert denied =~ ~r/\A確認します。\n\n\[Duet\] .*拒否された操作: Bash。/
    assert {:ok, response} = Duet.post("reviewer", "/compact")
    assert response =~ "<handoff>\n引き継ぎ要約\n</handoff>"
    assert response =~ "あなたのroleはreviewerです。"
    refute response =~ "old context"

    assert {:ok, ""} = Duet.post("reviewer", "/clear")
    assert {:ok, response} = Duet.post("reviewer", "new context")
    assert response =~ "あなたのroleはreviewerです。"
    refute response =~ "<handoff>"
    assert Enum.count(records(log), &Map.has_key?(&1, "args")) == 3

    assert {:ok, _} = Duet.post("reviewer", "empty summary")
    assert {:error, :empty_compact_summary} = Duet.post("reviewer", "/compact")
    assert {:ok, "empty summary\nnext"} = Duet.post("reviewer", "next")
  end

  test "SIGINT interrupts the port and queued work resumes the same conversation", ctx do
    {pid, log} = interrupt_entry(ctx, "ack")
    task = Task.async(fn -> Duet.post("interrupt", "wait") end)
    wait_for(fn -> File.read!(log) =~ ~s("wait") end)

    assert {:error, :busy} = Duet.post("interrupt", "busy")
    assert {:ok, ["interrupt"]} = Duet.cast_all("queued")
    assert [%{backend: :agy, status: :busy, queued: 1}] = Duet.statuses()
    old_port = :sys.get_state(pid).port

    assert :ok = Duet.interrupt("interrupt")
    assert {:error, "interrupted"} = Task.await(task)
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
    assert Port.info(old_port) == nil

    [launch, wait, resumed, queued] = File.read!(log) |> String.split("\n", trim: true)
    refute launch =~ "--conversation"
    assert wait =~ ~s("wait")
    assert resumed =~ "--conversation test-conversation"
    assert queued =~ ~s("queued")
    assert {:error, :not_running} = Duet.interrupt("interrupt")
  end

  test "a turn finished before SIGINT keeps its result", ctx do
    {pid, _log} = interrupt_entry(ctx, "late")
    task = Task.async(fn -> Duet.post("interrupt", "wait") end)
    wait_for(fn -> :sys.get_state(pid).status == :waiting end)

    assert {:error, :not_running} = Duet.interrupt("interrupt")
    assert {:ok, "done"} = Task.await(task)
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
  end

  test "clear recovers an unconfirmed interrupt and preserves reservations", ctx do
    {pid, log} = interrupt_entry(ctx, "ignore")
    post = Task.async(fn -> Duet.post("interrupt", "wait") end)
    wait_for(fn -> File.read!(log) =~ ~s("wait") end)
    assert {:ok, ["interrupt"]} = Duet.cast_all("queued")

    interrupt = Task.async(fn -> Duet.interrupt("interrupt") end)
    wait_for(fn -> :sys.get_state(pid).status == :interrupting end)
    port = :sys.get_state(pid).port
    send(pid, {:interrupt_timeout, port})

    assert {:error, :interrupt_timeout} = Task.await(interrupt)
    assert {:error, :interrupt_timeout} = Task.await(post)
    assert [%{status: :interrupt_unknown, queued: 1}] = Duet.statuses()
    assert {:error, :interrupt_timeout} = Duet.post("interrupt", "blocked")
    assert {:ok, ""} = Duet.post("interrupt", "/clear")
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
    assert Port.info(port) == nil

    [_, _, launch, queued] = File.read!(log) |> String.split("\n", trim: true)
    refute launch =~ "--conversation"
    assert queued =~ ~s("queued")
  end

  test "startup failure is visible and leaves a healthy sibling running", ctx do
    start_supervised!(Duet.EntrySupervisor)
    {log, good} = config(ctx, "good")
    {_bad_log, bad} = config(ctx, "bad", command: fake_command(log) <> " --bad-startup")
    Registry.put_meta(Duet.EntryRegistry, :configured_entries, [bad, good])

    assert {:ok, healthy} = Duet.EntrySupervisor.start_entry(good)
    assert {:ok, pid} = Duet.EntrySupervisor.start_entry(bad)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid,
                    {:shutdown, {:initialize_failed, "invalid model"}}},
                   2_000

    wait_for(fn -> :sys.get_state(healthy).status == :idle end)
    assert [failed, ready] = Duet.statuses()
    assert %{backend: :agy, status: :failed} = failed
    assert %{backend: :agy, status: :ready} = ready
    assert {:ok, "still running"} = Duet.post("good", "still running")
  end

  defp interrupt_entry(ctx, handling) do
    script = Path.join(ctx.dir, "interrupt.sh")
    log = Path.join(ctx.dir, "interrupt.log")

    File.write!(script, ~S"""
    log=$1
    handling=$2
    shift 2
    printf '%s\n' "$*" >> "$log"
    if [[ "$handling" == "ignore" ]]; then
      trap '' INT
    elif [[ "$handling" == "late" ]]; then
      trap 'echo "{\"event\":\"result\",\"result\":{\"status\":\"SUCCESS\",\"response\":\"done\"}}"; echo "{\"event\":\"result\",\"result\":{\"status\":\"ERROR\",\"error\":\"stream input cancelled: context canceled\",\"finished_reason\":\"interrupted\"}}"; exit 1' INT
    else
      trap 'echo "{\"event\":\"result\",\"result\":{\"status\":\"ERROR\",\"error\":\"interrupted\",\"finished_reason\":\"interrupted\"}}"; exit 1' INT
    fi
    echo '{"event":"init","conversation_id":"test-conversation"}'
    while IFS= read -r line; do
      printf '%s\n' "$line" >> "$log"
      if [[ "$line" == *'"wait"'* ]]; then
        read -r unexpected
      else
        echo '{"event":"result","result":{"status":"SUCCESS","response":"resumed"}}'
      fi
    done
    """)

    {_unused, config} = config(ctx, "interrupt", command: "bash #{script} #{log} #{handling}")
    {start_entry(config), log}
  end

  defp config(ctx, name, opts \\ []) do
    log = Path.join(ctx.dir, "#{name}.jsonl")
    entry = Map.merge(%{name: name, backend: "agy", command: fake_command(log)}, Map.new(opts))
    File.write!(ctx.path, "---\n#{JSON.encode!(%{entries: [entry]})}\n---\n")
    assert {:ok, %{entries: [config]}} = Duet.Config.parse(ctx.path)
    {log, config}
  end

  defp fake_command(log) do
    script = Path.expand("../support/fake_agy.script", __DIR__)
    "elixir #{script} #{log}"
  end

  defp start_entry(config) do
    pid = start_supervised!({Duet.Entry, config})
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
    pid
  end

  defp records(log),
    do: File.read!(log) |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp wait_for(fun, attempts \\ 200)
  defp wait_for(_fun, 0), do: flunk("entry did not reach expected state")

  defp wait_for(fun, attempts) do
    unless fun.() do
      Process.sleep(10)
      wait_for(fun, attempts - 1)
    end
  end
end
