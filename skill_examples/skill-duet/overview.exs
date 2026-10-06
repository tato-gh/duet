# Usage: elixir --sname NAME@localhost overview.exs ENTRY_NAME

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via overview.exs")
  System.halt(1)
end

Code.require_file("client.exs", __DIR__)

Node.set_cookie(:duet_cookie)

case System.argv() do
  [entry_name] ->
    node = DuetScript.get_node_name() |> DuetScript.node_atom()
    Node.connect(node)

    case :erpc.call(node, Duet, :overview, [entry_name], :infinity) do
      {:ok, response} ->
        IO.puts(response)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{DuetScript.error_text(reason)}")
        System.halt(1)
    end

  _ ->
    IO.puts(:stderr, "Usage: elixir --sname NAME@localhost overview.exs ENTRY_NAME")
    System.halt(1)
end
