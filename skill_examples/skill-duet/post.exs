# Usage: elixir --sname NAME@localhost post.exs ENTRY_NAME PROMPT

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via post.exs")
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
  [entry_name | prompt_parts] when prompt_parts != [] ->
    prompt = Enum.join(prompt_parts, " ")
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    case :erpc.call(node, Duet, :post, [entry_name, prompt], :infinity) do
      {:ok, response} ->
        IO.puts(response)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir --sname NAME@localhost post.exs ENTRY_NAME PROMPT")
    System.halt(1)
end
