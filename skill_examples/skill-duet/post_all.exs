# Usage: elixir --sname NAME@localhost post_all.exs PROMPT

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via post_all.exs")
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
  prompt_parts when prompt_parts != [] ->
    prompt = Enum.join(prompt_parts, " ")
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    case :erpc.call(node, Duet, :post_all, [prompt], 600_000) do
      results when is_list(results) ->
        Enum.each(results, fn
          {entry, {:ok, response}} -> IO.puts("[#{entry}]\n#{response}\n")
          {entry, {:error, reason}} -> IO.puts(:stderr, "[#{entry}] Error: #{inspect(reason)}")
        end)

        if Enum.any?(results, fn {_entry, result} -> match?({:error, _}, result) end) do
          System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir --sname NAME@localhost post_all.exs PROMPT")
    System.halt(1)
end
