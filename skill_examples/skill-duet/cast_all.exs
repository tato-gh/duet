# Usage: elixir --sname NAME@localhost cast_all.exs PROMPT

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via cast_all.exs")
  System.halt(1)
end

Code.require_file("client.exs", __DIR__)

Node.set_cookie(:duet_cookie)

case System.argv() do
  prompt_parts when prompt_parts != [] ->
    prompt = Enum.join(prompt_parts, " ")
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    case :erpc.call(node, Duet, :cast_all, [prompt], 10_000) do
      {:ok, entries} ->
        Enum.each(entries, &IO.puts("Reserved: #{&1}"))

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{DuetScript.error_text(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir --sname NAME@localhost cast_all.exs PROMPT")
    System.halt(1)
end
