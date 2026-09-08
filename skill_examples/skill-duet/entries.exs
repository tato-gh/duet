# Usage: elixir --sname NAME@localhost entries.exs

Code.require_file("client.exs", __DIR__)

Node.set_cookie(:duet_cookie)

node = DuetScript.get_node_name() |> DuetScript.node_atom()
Node.connect(node)

case :erpc.call(node, Duet, :entries, [], 5_000) do
  entries when is_list(entries) ->
    Enum.each(entries, fn entry ->
      name = Map.get(entry, :name, "unknown")
      role = Map.get(entry, :role, "no role")
      IO.puts("- #{name}: #{role}")
    end)

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{inspect(reason)}")
    System.halt(1)
end
