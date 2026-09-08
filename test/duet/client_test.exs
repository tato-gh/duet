Code.require_file("../../skill_examples/skill-duet/client.exs", __DIR__)

defmodule Duet.ClientTest do
  use ExUnit.Case, async: true

  setup do
    path = Path.join(System.tmp_dir!(), "duet-client-#{System.unique_integer([:positive])}.md")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "client and server resolve quoted and commented node names alike", %{path: path} do
    for value <- ["duet", "'duet'", ~s("duet"), "duet # local", "'duet@localhost' # local"] do
      File.write!(path, "---\nnode_name: #{value}\nentries: []\n---\n")
      assert {:ok, config} = Duet.Config.parse(path)
      assert DuetScript.get_node_name(path) == config.node_name
    end
  end

  test "client and server use the same default with no node_name or no file", %{path: path} do
    assert {:ok, config} = Duet.Config.parse(path)
    assert DuetScript.get_node_name(path) == config.node_name

    File.write!(path, "---\nentries: []\n---\nnode_name: wrong-node\n")
    assert {:ok, config} = Duet.Config.parse(path)
    assert DuetScript.get_node_name(path) == config.node_name
  end

  test "client and server resolve indented root mappings alike", %{path: path} do
    for indent <- ["", "  ", "    "],
        root_lines <- [
          ["node_name: custom_duet", "entries: []"],
          ["entries: []", "node_name: 'custom_duet' # local"]
        ] do
      front_matter = Enum.map_join(root_lines, "\n", &(indent <> &1))
      File.write!(path, "---\n# root comment\n\n      # indented comment\n#{front_matter}\n---\n")

      assert {:ok, config} = Duet.Config.parse(path)
      assert config.node_name == "custom_duet"
      assert DuetScript.get_node_name(path) == config.node_name
    end
  end

  test "indented nested keys and role text do not select the connection target", %{path: path} do
    for root_node <- ["", "  node_name: custom_duet\n"] do
      File.write!(path, """
      ---
        entries:
          - name: worker
            node_name: nested_node
            role: |
              node_name: role_text
      #{root_node}---
      """)

      assert {:ok, config} = Duet.Config.parse(path)
      assert DuetScript.get_node_name(path) == config.node_name
    end
  end

  test "unsupported node syntax is reported rather than used as a connection target" do
    assert_raise ArgumentError, ~r/node_name must be a single-line identifier/, fn ->
      DuetScript.node_name_from_content("---\nnode_name: >\n  duet\n---\n")
    end
  end
end
