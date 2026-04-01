# Usage: elixir post_parallel.exs ENTRY1 PROMPT1 ENTRY2 PROMPT2 ...
#
# Example:
#   elixir post_parallel.exs review "コードをレビューして" summary "PRを要約して"
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
  args when args != [] and rem(length(args), 2) == 0 ->
    node_name = DuetScript.get_node_name()
    node = String.to_atom("#{node_name}@localhost")
    Node.connect(node)

    calls =
      args
      |> Enum.chunk_every(2)
      |> Enum.map(fn [entry, prompt] -> {entry, prompt} end)

    results =
      calls
      |> Enum.map(fn {entry, prompt} ->
        Task.async(fn ->
          {entry, :erpc.call(node, Duet.ErpcChannel, :post, [entry, prompt], 300_000)}
        end)
      end)
      |> Task.await_many(300_000)

    Enum.each(results, fn
      {entry, {:ok, response}} ->
        IO.puts("[#{entry}]\n#{response}\n")

      {entry, {:error, reason}} ->
        IO.puts(:stderr, "[#{entry}] Error: #{inspect(reason)}")
    end)

  _ ->
    IO.puts(:stderr, "Usage: elixir post_parallel.exs ENTRY1 PROMPT1 ENTRY2 PROMPT2 ...")
    System.halt(1)
end
