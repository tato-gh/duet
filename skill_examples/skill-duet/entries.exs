# Usage: elixir --sname NAME@localhost entries.exs

Code.require_file("client.exs", __DIR__)

Node.set_cookie(:duet_cookie)

node = DuetScript.get_node_name() |> DuetScript.node_atom()
Node.connect(node)

operation =
  case System.argv() do
    [] ->
      :entries

    ["--status"] ->
      :statuses

    _ ->
      IO.puts(:stderr, "Usage: elixir --sname NAME@localhost entries.exs [--status]")
      System.halt(1)
  end

case :erpc.call(node, Duet, operation, [], 5_000) do
  entries when is_list(entries) ->
    Enum.each(entries, fn entry ->
      name = Map.get(entry, :name, "unknown")
      role = Map.get(entry, :role, "no role")

      if operation == :statuses do
        IO.puts(
          "- #{name} [#{entry.backend}/#{entry.status}, queued=#{inspect(entry.queued)}]: #{role}"
        )

        if entry.reason, do: IO.puts("  Error: #{DuetScript.error_text(entry.reason)}")
      else
        IO.puts("- #{name}: #{role}")
      end
    end)

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{inspect(reason)}")
    System.halt(1)
end
