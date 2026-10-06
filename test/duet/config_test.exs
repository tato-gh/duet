defmodule Duet.ConfigTest do
  use ExUnit.Case, async: true

  test "parse/1 reads DUET.md entries" do
    path =
      tmp_file("""
      ---
      node_name: "duet"
      entries:
        - name: "chat_play"
          command: "codex app-server"
          role: "chat role"
          model: "gpt-5.6-luna"
          reasoning_effort: "high"
          service_tier: "fast"
          approval_policy: "never"
          thread_sandbox: "read-only"
          turn_sandbox_policy:
            type: "readOnly"
            networkAccess: false
      ---
      """)

    assert {:ok, config} = Duet.Config.parse(path)
    assert config.node_name == "duet"
    assert [%{name: "chat_play", role: "chat role"}] = config.entries
    assert hd(config.entries).model == "gpt-5.6-luna"
    assert hd(config.entries).reasoning_effort == "high"
    assert hd(config.entries).service_tier == "fast"
    assert hd(config.entries).turn_sandbox_policy["type"] == "readOnly"
  end

  test "parse/1 rejects duplicate entry names" do
    path =
      tmp_file("""
      ---
      entries:
        - name: "same"
        - name: "same"
      ---
      """)

    assert {:error, message} = Duet.Config.parse(path)
    assert message =~ "Duplicate entry names"
  end

  test "parse/1 ignores unsupported service_tier values" do
    path =
      tmp_file("""
      ---
      entries:
        - name: "boolean"
          service_tier: true
        - name: "unknown"
          service_tier: "standard"
        - name: "collection"
          service_tier: ["fast"]
        - name: "invalid-model-settings"
          model: true
          reasoning_effort: "impossibly-high"
      ---
      """)

    assert {:ok, config} = Duet.Config.parse(path)
    assert Enum.map(config.entries, & &1.service_tier) == [nil, nil, nil, nil]
    assert Enum.at(config.entries, 3).model == nil
    assert Enum.at(config.entries, 3).reasoning_effort == nil
  end

  test "parse/1 rejects unknown top-level keys" do
    path =
      tmp_file("""
      ---
      unknown_key: true
      ---
      """)

    assert {:error, message} = Duet.Config.parse(path)
    assert message =~ "Unknown DUET.md keys"
  end

  test "backends can coexist and existing entries default to codex" do
    path =
      tmp_file("""
      ---
      entries:
        - name: old
        - name: explicit
          backend: codex
        - name: reviewer
          backend: claude
          model: sonnet
          reasoning_effort: high
      ---
      """)

    assert {:ok, %{entries: [old, explicit, claude]}} = Duet.Config.parse(path)
    assert old.backend == :codex
    assert explicit.command == "codex app-server"
    assert claude.backend == :claude
    assert claude.command == "claude"
    assert claude.model == "sonnet"
    assert claude.reasoning_effort == "high"
    assert claude.permission_mode == "dontAsk"
    assert claude.tools == ["Read", "Glob", "Grep"]
    refute Map.has_key?(claude, :thread_sandbox)
  end

  test "claude configuration rejects unsupported and malformed settings" do
    for setting <- [
          "service_tier: fast",
          "thread_sandbox: read-only",
          "turn_sandbox_policy: {}",
          "approval_policy: never",
          "reasoning_effort: none",
          "permission_mode: typo",
          "tools: default",
          "allowed_tools: [true]",
          "command: null",
          "model: true",
          "role: []",
          "typo: value"
        ] do
      path = tmp_file("---\nentries:\n  - name: bad\n    backend: claude\n    #{setting}\n---\n")
      assert {:error, message} = Duet.Config.parse(path), setting
      assert message =~ "bad"
    end
  end

  test "backend typos and claude-only settings on codex are rejected" do
    for setting <- ["backend: typo", "backend: null", "permission_mode: dontAsk", "tools: []"] do
      path = tmp_file("---\nentries:\n  - name: bad\n    #{setting}\n---\n")
      assert {:error, _} = Duet.Config.parse(path)
    end
  end

  test "claude accepts explicit tools and a custom executable" do
    path =
      tmp_file("""
      ---
      entries:
        - name: worker
          backend: claude
          command: /opt/claude
          permission_mode: acceptEdits
          tools: [Read, Edit, Bash]
          allowed_tools: ["Bash(mix test *)"]
      ---
      """)

    assert {:ok, %{entries: [entry]}} = Duet.Config.parse(path)
    assert entry.command == "/opt/claude"
    assert entry.tools == ["Read", "Edit", "Bash"]
    assert entry.allowed_tools == ["Bash(mix test *)"]
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "duet-config-#{System.unique_integer([:positive])}.md")
    File.write!(path, content)
    path
  end
end
