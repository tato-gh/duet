# Usage: elixir post_parallel.exs NODE_NAME ENTRY1 PROMPT1 ENTRY2 PROMPT2 ...
#
# Example:
#   elixir post_parallel.exs duet@myhostname review "コードをレビューして" summary "PRを要約して"

case System.argv() do
  [node_name | rest] when rest != [] and rem(length(rest), 2) == 0 ->
    node = String.to_atom(node_name)
    Node.connect(node)

    calls =
      rest
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
    IO.puts(:stderr, "Usage: elixir post_parallel.exs NODE_NAME ENTRY1 PROMPT1 ENTRY2 PROMPT2 ...")
    System.halt(1)
end
