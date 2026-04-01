# Usage: elixir entries.exs
#
# Lists all available entries with their names and roles.
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

node_name = DuetScript.get_node_name()
node = String.to_atom("#{node_name}@localhost")
Node.connect(node)

case :erpc.call(node, Duet.ErpcChannel, :entries, [], 5_000) do
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
