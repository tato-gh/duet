defmodule DuetScript do
  @moduledoc false

  # Keep the standalone scripts dependency-free. Only the top-level, single-line
  # node_name scalar is read here; other configuration belongs to the server.
  def get_node_name(path \\ Path.join(File.cwd!(), "DUET.md")) do
    case File.read(path) do
      {:ok, content} -> node_name_from_content(content)
      {:error, :enoent} -> default_node_name()
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def node_name_from_content(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", front_matter, _body] ->
        indent = top_level_indent(front_matter)

        case Regex.scan(~r/^#{indent}node_name:[ \t]*(.*)$/m, front_matter) do
          [] -> default_node_name()
          [[_, value]] -> parse_node_name(String.trim(value))
          _ -> raise ArgumentError, "DUET.md contains duplicate node_name keys"
        end

      _ ->
        raise ArgumentError, "DUET.md must have YAML front matter (--- ... ---)"
    end
  end

  defp top_level_indent(front_matter) do
    # The first non-blank, non-comment line establishes the root mapping's indent.
    # Match that exact indent so nested keys and block scalar text stay excluded.
    case Regex.run(~r/^( *)(?=[^\s#])/m, front_matter) do
      [_, indent] -> indent
      nil -> ""
    end
  end

  def node_atom(node_name) do
    if String.contains?(node_name, "@") do
      String.to_atom(node_name)
    else
      String.to_atom("#{node_name}@localhost")
    end
  end

  defp default_node_name do
    {:ok, hostname} = :inet.gethostname()
    "duet@#{hostname}"
  end

  defp parse_node_name(value) do
    # Node identifiers need no YAML escapes. Accept plain, single-quoted and
    # double-quoted identifiers, with optional trailing YAML comments.
    patterns = [
      ~r/^'([A-Za-z0-9_.@-]+)'(?:[ \t]+\#.*)?$/,
      ~r/^"([A-Za-z0-9_.@-]+)"(?:[ \t]+\#.*)?$/,
      ~r/^([A-Za-z0-9_.@-]+)(?:[ \t]+\#.*)?$/
    ]

    name =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, value) do
          [_, name] -> name
          _ -> nil
        end
      end)

    name ||
      raise ArgumentError,
            "node_name must be a single-line identifier using letters, digits, _, ., @ or -; " <>
              "plain, single-quoted and double-quoted values are supported"
  end
end
