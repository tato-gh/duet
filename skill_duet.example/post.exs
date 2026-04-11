# Usage: elixir post.exs ENTRY_NAME PROMPT
#
# Example:
#   elixir post.exs review "このコードをレビューして"
#
# Automatically reads node_name from DUETFLOW.md in the current or parent directory.
# If not found, defaults to "duet@localhost"

defmodule DuetScript do
  def get_node_name do
    case read_duetflow() do
      {:ok, content} ->
        case Regex.run(~r/node_name:\s*"?([^"\n]+)"?/, content) do
          [_, node_name] -> String.trim(node_name)
          _ -> "duet"
        end

      {:error, :enoent} ->
        "duet"
    end
  end

  defp read_duetflow do
    cwd = File.cwd!()
    File.read(Path.join(cwd, "DUETFLOW.md"))
  end
end

Node.set_cookie(:duet_cookie)

case System.argv() do
  [entry_name | prompt_parts] when prompt_parts != [] ->
    prompt = Enum.join(prompt_parts, " ")
    node_name = DuetScript.get_node_name()
    node = String.to_atom("#{node_name}@localhost")
    Node.connect(node)

    case :erpc.call(node, Duet.ErpcChannel, :post, [entry_name, prompt], 300_000) do
      {:ok, response} ->
        IO.binwrite(:stdio, response <> "\n")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir post.exs ENTRY_NAME PROMPT")
    System.halt(1)
end
