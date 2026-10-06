# Usage: elixir --sname NAME@localhost overview_all.exs

if System.get_env("CODEX_DUET_ENTRY") == "1" do
  IO.puts(:stderr, "Error: a Duet entry cannot call Duet via overview_all.exs")
  System.halt(1)
end

Code.require_file("client.exs", __DIR__)

Node.set_cookie(:duet_cookie)
node = DuetScript.get_node_name() |> DuetScript.node_atom()
Node.connect(node)

case :erpc.call(node, Duet, :overview_all, [], :infinity) do
  results when is_list(results) ->
    Enum.each(results, fn
      {entry, {:ok, response}} ->
        IO.puts("[#{entry}]\n#{response}\n")

      {entry, {:error, reason}} ->
        IO.puts(:stderr, "[#{entry}] Error: #{DuetScript.error_text(reason)}")
    end)

    if Enum.any?(results, fn {_entry, result} -> match?({:error, _}, result) end) do
      System.halt(1)
    end

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{DuetScript.error_text(reason)}")
    System.halt(1)
end
