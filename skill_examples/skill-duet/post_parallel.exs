# Usage: elixir --sname NAME@localhost post_parallel.exs ENTRY1 PROMPT1 ENTRY2 PROMPT2 ...

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via post_parallel.exs")
  System.halt(1)
end

defmodule DuetScript do
  def get_node_name do
    case File.read(Path.join(File.cwd!(), "DUET.md")) do
      {:ok, content} ->
        case Regex.run(~r/node_name:\s*"?([^"\n]+)"?/, content) do
          [_, node_name] -> String.trim(node_name)
          _ -> "duet"
        end

      {:error, :enoent} ->
        "duet"
    end
  end

  def node_atom(node_name) do
    if String.contains?(node_name, "@") do
      String.to_atom(node_name)
    else
      String.to_atom("#{node_name}@localhost")
    end
  end
end

Node.set_cookie(:duet_cookie)

case System.argv() do
  args when args != [] and rem(length(args), 2) == 0 ->
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    results =
      args
      |> Enum.chunk_every(2)
      |> Enum.map(fn [entry, prompt] ->
        Task.async(fn ->
          {entry, :erpc.call(node, Duet, :post, [entry, prompt], 300_000)}
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
    IO.puts(
      :stderr,
      "Usage: elixir --sname NAME@localhost post_parallel.exs ENTRY1 PROMPT1 ENTRY2 PROMPT2 ..."
    )
    System.halt(1)
end
