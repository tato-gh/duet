# Usage: elixir post.exs NODE_NAME ENTRY_NAME PROMPT
#
# Example:
#   elixir post.exs duet@myhostname review "このコードをレビューして"

case System.argv() do
  [node_name, entry_name | prompt_parts] when prompt_parts != [] ->
    prompt = Enum.join(prompt_parts, " ")
    node = String.to_atom(node_name)
    Node.connect(node)

    case :erpc.call(node, Duet.ErpcChannel, :post, [entry_name, prompt], 300_000) do
      {:ok, response} ->
        IO.puts(response)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir post.exs NODE_NAME ENTRY_NAME PROMPT")
    System.halt(1)
end
