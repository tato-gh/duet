defmodule Duet.DuetflowTest do
  use ExUnit.Case

  defp write_tmp(content) do
    path = Path.join(System.tmp_dir!(), "duetflow_#{:erlang.unique_integer([:positive])}.md")
    File.write!(path, content)
    path
  end

  test "parse/1 with minimal valid YAML front-matter" do
    path =
      write_tmp("""
      ---
      ---
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    assert config.diff_watch.enabled == true
    assert config.erpc_channel == []
    assert is_binary(config.node_name)
    assert String.starts_with?(config.node_name, "duet@")
  end

  test "parse/1 sets node_name from YAML" do
    path =
      write_tmp("""
      ---
      node_name: "myduet@testhost"
      ---
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    assert config.node_name == "myduet@testhost"
  end

  test "parse/1 builds diff_watch config from YAML" do
    path =
      write_tmp("""
      ---
      diff_watch:
        enabled: false
        command: "codex custom"
        poll_interval: 500
        include_untracked: true
        file_change_approval: "approve"
        prompt: "review this diff"
      ---
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    dw = config.diff_watch
    assert dw.enabled == false
    assert dw.command == "codex custom"
    assert dw.poll_interval == 500
    assert dw.include_untracked == true
    assert dw.file_change_approval == "approve"
    assert dw.prompt == "review this diff"
  end

  test "parse/1 uses default diff_watch values when key absent" do
    path =
      write_tmp("""
      ---
      node_name: "duet@host"
      ---
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    dw = config.diff_watch
    assert dw.enabled == true
    assert dw.command == "codex app-server"
    assert dw.diff_command == "git diff HEAD"
    assert dw.poll_interval == 1000
    assert dw.include_untracked == false
    assert dw.file_change_approval == "reject"
    assert dw.prompt == ""
  end

  test "parse/1 builds erpc_channel entries" do
    path =
      write_tmp("""
      ---
      erpc_channel:
        - name: "review"
          enabled: true
          command: "codex app-server"
          role: "コードレビュアー"
        - name: "summary"
      ---
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    assert length(config.erpc_channel) == 2
    [review, summary] = config.erpc_channel
    assert review.name == "review"
    assert review.enabled == true
    assert review.command == "codex app-server"
    assert review.role == "コードレビュアー"
    assert summary.name == "summary"
    assert summary.enabled == true
    assert summary.role == ""
  end

  test "parse/1 returns error on duplicate erpc_channel names" do
    path =
      write_tmp("""
      ---
      erpc_channel:
        - name: "dup"
        - name: "other"
        - name: "dup"
      ---
      """)

    assert {:error, msg} = Duet.Duetflow.parse(path)
    assert msg =~ "Duplicate erpc_channel entry names"
    assert msg =~ "dup"
  end

  test "parse/1 returns default config when file does not exist" do
    assert {:ok, config} = Duet.Duetflow.parse("/nonexistent/path/DUETFLOW.md")
    assert config.diff_watch.enabled == true
    assert config.diff_watch.command == "codex app-server"
    assert config.diff_watch.diff_command == "git diff HEAD"
    assert config.erpc_channel == []
    assert String.starts_with?(config.node_name, "duet@")
  end

  test "parse/1 returns error when front-matter is missing" do
    path = write_tmp("just plain text without front-matter\n")
    assert {:error, msg} = Duet.Duetflow.parse(path)
    assert msg =~ "front-matter"
  end

  test "parse/1 returns error when erpc_channel entry is missing name" do
    path =
      write_tmp("""
      ---
      erpc_channel:
        - enabled: true
          prompt: "no name here"
      ---
      """)

    assert {:error, msg} = Duet.Duetflow.parse(path)
    assert msg =~ "missing required field 'name'"
  end

  test "parse/1 returns error on invalid YAML" do
    path =
      write_tmp("""
      ---
      invalid: yaml: [broken
      ---
      """)

    assert {:error, msg} = Duet.Duetflow.parse(path)
    assert msg =~ "Failed to parse YAML"
  end

  test "parse/1 accepts body text after front-matter (body is ignored)" do
    path =
      write_tmp("""
      ---
      node_name: "duet@host"
      ---
      This body text is ignored.
      """)

    assert {:ok, config} = Duet.Duetflow.parse(path)
    assert config.node_name == "duet@host"
  end
end
