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
