# Usage: elixir --sname NAME@localhost interrupt.exs ENTRY_NAME

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via interrupt.exs")
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
  [entry_name] ->
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    case :erpc.call(node, Duet, :interrupt, [entry_name], 5_000) do
      :ok ->
        IO.puts("Interruption requested: #{entry_name}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir --sname NAME@localhost interrupt.exs ENTRY_NAME")
    System.halt(1)
end
