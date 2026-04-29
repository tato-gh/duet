# Usage: elixir --sname NAME@localhost entries.exs

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
