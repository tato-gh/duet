defmodule Duet.ClaudeEntryTest do
  use ExUnit.Case

  setup do
    start_supervised!({Registry, keys: :unique, name: Duet.EntryRegistry})
    dir = Path.join(System.tmp_dir!(), "duet-claude-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "DUET.md")
    Duet.Config.set_config_file(path)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, path: path}
  end

  test "configured Claude keeps one process and context, injects role once, and isolates entries",
       ctx do
    {pid, log} =
      start_entry(ctx, "reviewer", role: "レビュー担当", model: "sonnet", reasoning_effort: "high")

    {_other, other_log} = start_entry(ctx, "other")
    assert {:ok, first} = Duet.post("reviewer", "こんにちは")
    assert first =~ "あなたのroleはレビュー担当です。"
    assert {:ok, second} = Duet.post("reviewer", "続き")
    assert second =~ first
    assert second =~ "続き"
    assert {:ok, "別の会話"} = Duet.post("other", "別の会話")
    assert :sys.get_state(pid).session_id != ""
    [one, two] = inputs(log)
    assert one =~ "レビュー担当"
    assert two == "続き"
    assert inputs(other_log) == ["別の会話"]
    [launch] = launches(log)
    assert launch["entry"] == "reviewer"
    assert Enum.chunk_every(launch["args"], 2, 1, :discard) |> Enum.member?(["--model", "sonnet"])
    assert Enum.member?(launch["args"], "Read,Glob,Grep")
    assert Enum.member?(launch["args"], "dontAsk")
    assert Enum.member?(launch["args"], "high")
  end

  test "clear starts a fresh session and reapplies role", ctx do
    {pid, log} = start_entry(ctx, "clear", role: "役割")
    assert {:ok, _} = Duet.post("clear", "old context")
    old_port = :sys.get_state(pid).port
    assert {:ok, ""} = Duet.post("clear", "/clear")
    assert Port.info(old_port) == nil
    assert {:ok, response} = Duet.post("clear", "new context")
    refute response =~ "old context"
    assert response =~ "役割"
    assert length(launches(log)) == 2
  end

  test "compact summarizes then hands off to a fresh session", ctx do
    {_pid, log} = start_entry(ctx, "compact", role: "reviewer")
    assert {:ok, _} = Duet.post("compact", "old context")
    assert {:ok, response} = Duet.post("compact", "/compact")
    assert response =~ "<handoff>\n引き継ぎ要約\n</handoff>"
    assert response =~ "あなたのroleはreviewerです。"
    refute response =~ "old context"
    assert length(launches(log)) == 2
  end

  test "empty compact summary preserves the existing session", ctx do
    {_pid, log} = start_entry(ctx, "empty")
    assert {:ok, _} = Duet.post("empty", "empty summary")
    assert {:error, :empty_compact_summary} = Duet.post("empty", "/compact")
    assert length(launches(log)) == 1
    assert {:ok, response} = Duet.post("empty", "next")
    assert response =~ "empty summary"
  end

  test "interrupt and queued posts work with either acknowledgement ordering", ctx do
    for {prompt, name} <- [{"wait", "ack-first"}, {"result before ack", "result-first"}] do
      {pid, log} = start_entry(ctx, name)
      task = Task.async(fn -> Duet.post(name, prompt) end)
      wait_for(fn -> :sys.get_state(pid).status == :waiting end)
      assert {:error, :busy} = Duet.post(name, "busy")
      assert :ok = GenServer.call(pid, {:enqueue, "queued"})

      assert %{backend: :claude, status: :busy, queued: 1} =
               Enum.find(Duet.statuses(), &(&1.name == name))

      assert :ok = Duet.interrupt(name)
      assert {:error, "interrupted"} = Task.await(task)
      wait_for(fn -> :sys.get_state(pid).status == :idle end)
      assert inputs(log) == [prompt, "queued"]
      assert {:error, :not_running} = Duet.interrupt(name)
    end
  end

  test "rejected interruption preserves a normal result", ctx do
    {pid, _log} = start_entry(ctx, "reject")
    task = Task.async(fn -> Duet.post("reject", "reject interrupt") end)
    wait_for(fn -> :sys.get_state(pid).status == :waiting end)
    assert {:error, {:control_error, "cannot interrupt"}} = Duet.interrupt("reject")
    assert {:ok, "finished normally"} = Task.await(task)
  end

  test "missing interrupt acknowledgement can be recovered with clear without losing the queue",
       ctx do
    {pid, log} = start_entry(ctx, "missing-ack")
    post = Task.async(fn -> Duet.post("missing-ack", "missing ack") end)
    wait_for(fn -> :sys.get_state(pid).status == :waiting end)
    assert :ok = GenServer.call(pid, {:enqueue, "queued after recovery"})
    interrupt = Task.async(fn -> Duet.interrupt("missing-ack") end)
    wait_for(fn -> not is_nil(:sys.get_state(pid).completed_result) end)
    id = :sys.get_state(pid).interrupt_id
    send(pid, {:interrupt_timeout, id})
    assert {:error, :interrupt_timeout} = Task.await(interrupt)
    assert {:error, :interrupt_timeout} = Task.await(post)
    assert [%{status: :interrupt_unknown, queued: 1}] = Duet.statuses()
    assert {:error, :interrupt_timeout} = Duet.post("missing-ack", "must not run")
    assert inputs(log) == ["missing ack"]
    assert {:ok, ""} = Duet.post("missing-ack", "/clear")
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
    assert inputs(log) == ["missing ack", "queued after recovery"]
    assert length(launches(log)) == 2
  end

  test "permission requests are denied and unsupported control requests receive an error", ctx do
    start_entry(ctx, "permissions")
    assert {:ok, response} = Duet.post("permissions", "permission")
    assert get_in(JSON.decode!(response), ["response", "behavior"]) == "deny"
    assert {:ok, response} = Duet.post("permissions", "unsupported control")
    assert JSON.decode!(response)["subtype"] == "error"
  end

  test "model failures release the entry for the next request", ctx do
    start_entry(ctx, "failure")
    assert {:error, {:claude_error, "model failed"}} = Duet.post("failure", "fail")
    assert {:ok, "next"} = Duet.post("failure", "next")
  end

  test "empty errors arrays do not hide authentication failures", ctx do
    start_entry(ctx, "api-error")

    assert {:error, {:claude_error, "API Error: authentication failed"}} =
             Duet.post("api-error", "api failure")

    assert {:ok, "next"} = Duet.post("api-error", "next")
  end

  test "background continuations finish before responding, with either idle ordering", ctx do
    for {prompt, name} <- [
          {"background", "background-result-first"},
          {"background idle first", "background-idle-first"}
        ] do
      start_entry(ctx, name)
      assert {:ok, "complete result"} = Duet.post(name, prompt)
      assert {:ok, "next request result"} = Duet.post(name, "after background")
    end
  end

  test "CLI exit replies to the waiting caller", ctx do
    {pid, _log} = start_entry(ctx, "exit")
    ref = Process.monitor(pid)
    assert {:error, {:port_exit, 7}} = Duet.post("exit", "exit")
    assert_receive {:DOWN, ^ref, :process, ^pid, {:port_exit, 7}}
  end

  test "command arguments preserve literal shell characters" do
    config = %{
      command: "claude",
      permission_mode: "dontAsk",
      tools: [],
      allowed_tools: [],
      model: "a'$(touch bad)`echo bad`",
      reasoning_effort: nil
    }

    args = Duet.ClaudeEntry.command(config) |> OptionParser.split()
    assert List.last(args) == config.model
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.member?(["--tools", ""])
  end

  test "an independent entry does not inherit Claude Code's nesting marker", ctx do
    previous = System.get_env("CLAUDECODE")
    System.put_env("CLAUDECODE", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("CLAUDECODE", previous),
        else: System.delete_env("CLAUDECODE")
    end)

    {_pid, log} = start_entry(ctx, "nested")
    assert [launch] = launches(log)
    assert launch["claudecode"] == nil
  end

  test "broadcasts work across Codex and Claude entries", ctx do
    {claude, claude_log} = start_entry(ctx, "claude")
    codex_log = Path.join(ctx.dir, "codex.jsonl")
    File.write!(codex_log, "")
    script = Path.expand("../support/fake_app_server.script", __DIR__)

    config = %{
      name: "codex",
      backend: :codex,
      command: "FAKE_APP_SERVER_LOG=#{codex_log} elixir #{script}",
      role: "",
      approval_policy: "never",
      thread_sandbox: "read-only",
      turn_sandbox_policy: %{"type" => "readOnly", "networkAccess" => false}
    }

    codex = start_supervised!({Duet.Entry, config})
    wait_for(fn -> :sys.get_state(codex).status == :idle end)
    assert [{"claude", {:ok, "broadcast"}}, {"codex", {:ok, _}}] = Duet.post_all("broadcast")
    assert {:ok, ["claude", "codex"]} = Duet.cast_all("reserved")

    wait_for(fn ->
      :sys.get_state(claude).status == :idle and :sys.get_state(codex).status == :idle
    end)

    assert inputs(claude_log) == ["broadcast", "reserved"]
  end

  @tag :capture_log
  test "a failed Claude initialization does not restart or stop healthy supervised entries",
       ctx do
    supervisor = start_supervised!(Duet.EntrySupervisor)
    supervisor_ref = Process.monitor(supervisor)
    script = Path.expand("../support/fake_claude.script", __DIR__)
    log = Path.join(ctx.dir, "supervised.jsonl")

    good = %{
      name: "healthy",
      backend: :claude,
      role: "",
      model: nil,
      reasoning_effort: nil,
      permission_mode: "dontAsk",
      tools: [],
      allowed_tools: [],
      command: "elixir #{script} #{log}"
    }

    {:ok, healthy} = Duet.EntrySupervisor.start_entry(good)
    wait_for(fn -> :sys.get_state(healthy).status == :idle end)
    bad = %{good | name: "broken", command: good.command <> " --initialize-error"}
    Registry.put_meta(Duet.EntryRegistry, :configured_entries, [good, bad])
    {:ok, broken} = Duet.EntrySupervisor.start_entry(bad)
    ref = Process.monitor(broken)

    assert_receive {:DOWN, ^ref, :process, ^broken,
                    {:shutdown, {:initialize_failed, "initialization refused"}}},
                   2_000

    assert [{_, ^healthy, :worker, _}] = DynamicSupervisor.which_children(supervisor)
    assert {:ok, "still running"} = Duet.post("healthy", "still running")
    assert [failed, ready] = Duet.statuses()
    assert failed.name == "broken"
    assert failed.status == :failed
    assert failed.reason == {:shutdown, {:initialize_failed, "initialization refused"}}
    assert ready.name == "healthy"
    assert ready.status == :ready
    assert ready.backend == :claude
    refute_received {:DOWN, ^supervisor_ref, :process, ^supervisor, _}
  end

  defp start_entry(ctx, name, opts \\ []) do
    log = Path.join(ctx.dir, "#{name}.jsonl")
    script = Path.expand("../support/fake_claude.script", __DIR__)
    command = "elixir #{script} #{log}"
    entry = Map.merge(%{name: name, backend: "claude", command: command}, Map.new(opts))
    # JSON is a YAML subset, so exercise the public DUET.md configuration path.
    File.write!(ctx.path, "---\n#{JSON.encode!(%{entries: [entry]})}\n---\n")
    assert {:ok, %{entries: [config]}} = Duet.Config.parse(ctx.path)
    pid = start_supervised!({Duet.Entry, config})
    wait_for(fn -> :sys.get_state(pid).status == :idle end)
    {pid, log}
  end

  defp records(log),
    do: File.read!(log) |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp launches(log), do: Enum.filter(records(log), &Map.has_key?(&1, "args"))

  defp inputs(log) do
    for %{"received" => %{"type" => "user", "message" => %{"content" => text}}} <- records(log),
        do: text
  end

  defp wait_for(fun, attempts \\ 200)
  defp wait_for(_fun, 0), do: flunk("entry did not reach expected state")

  defp wait_for(fun, attempts) do
    unless fun.() do
      Process.sleep(10)
      wait_for(fun, attempts - 1)
    end
  end
end
