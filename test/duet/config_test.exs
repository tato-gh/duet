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

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "duet-config-#{System.unique_integer([:positive])}.md")
    File.write!(path, content)
    path
  end
end
