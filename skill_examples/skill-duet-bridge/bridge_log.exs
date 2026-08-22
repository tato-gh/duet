# Usage: elixir --sname NAME@localhost bridge_log.exs <read | read-after | publish | reset> [ARGUMENTS]

defmodule DuetBridgeLogScript do
  @timeout 5_000

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

  def connect do
    node = get_node_name() |> node_atom()

    case Node.connect(node) do
      true -> {:ok, node}
      false -> {:error, "could not connect to #{node}"}
      :ignored -> {:error, "the local Erlang node is not running"}
    end
  end

  def identity do
    if System.get_env("CODEX_DUET_ENTRY") == "1" do
      case System.get_env("CODEX_DUET_ENTRY_NAME") do
        nil -> {:error, "CODEX_DUET_ENTRY_NAME is not set"}
        "" -> {:error, "CODEX_DUET_ENTRY_NAME is not set"}
        entry_name -> {:ok, entry_name}
      end
    else
      {:ok, "bridge"}
    end
  end

  def current_branch do
    case git(["symbolic-ref", "--quiet", "--short", "HEAD"]) do
      {:ok, branch} when branch != "" ->
        {:ok, branch}

      _ ->
        case git(["rev-parse", "--verify", "--short", "HEAD"]) do
          {:ok, commit} when commit != "" -> {:ok, "detached@#{commit}"}
          _ -> {:error, "could not determine the current Git branch or detached commit"}
        end
    end
  end

  def call(node, function, arguments) do
    try do
      :erpc.call(node, Duet.BridgeLog, function, arguments, @timeout)
    catch
      :error, reason -> {:error, reason}
      :exit, reason -> {:error, reason}
    end
  end

  def parse_sequence(value) do
    case Integer.parse(value) do
      {sequence, ""} when sequence >= 0 -> {:ok, sequence}
      _ -> {:error, "SEQUENCE must be a non-negative integer"}
    end
  end

  def print_events(events) do
    Enum.each(events, fn event ->
      inserted_at =
        case event.inserted_at do
          %DateTime{} = value -> DateTime.to_iso8601(value)
          value -> inspect(value)
        end

      IO.puts(
        "[#{event.sequence}] sender=#{event.sender} branch=#{event.branch} at=#{inserted_at}\n#{event.body}\n"
      )
    end)
  end

  def halt_error(message) do
    IO.puts(:stderr, "Error: #{format_error(message)}")
    System.halt(1)
  end

  defp format_error(message) when is_binary(message), do: message
  defp format_error(message), do: inspect(message)

  defp git(arguments) do
    case System.cmd("git", arguments, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {_output, _status} -> :error
    end
  end
end

Node.set_cookie(:duet_cookie)

case System.argv() do
  ["read"] ->
    with {:ok, identity} <- DuetBridgeLogScript.identity(),
         {:ok, node} <- DuetBridgeLogScript.connect(),
         {:ok, events} <- DuetBridgeLogScript.call(node, :read_unread, [identity]) do
      DuetBridgeLogScript.print_events(events)
    else
      {:error, reason} -> DuetBridgeLogScript.halt_error(reason)
    end

  ["read-after", value] ->
    with {:ok, sequence} <- DuetBridgeLogScript.parse_sequence(value),
         {:ok, node} <- DuetBridgeLogScript.connect(),
         {:ok, events} <- DuetBridgeLogScript.call(node, :read_after, [sequence]) do
      DuetBridgeLogScript.print_events(events)
    else
      {:error, reason} -> DuetBridgeLogScript.halt_error(reason)
    end

  ["publish" | body_parts] when body_parts != [] ->
    body = Enum.join(body_parts, " ")

    with {:ok, sender} <- DuetBridgeLogScript.identity(),
         {:ok, branch} <- DuetBridgeLogScript.current_branch(),
         {:ok, node} <- DuetBridgeLogScript.connect(),
         {:ok, event} <- DuetBridgeLogScript.call(node, :publish, [sender, branch, body]) do
      IO.puts("Published: #{event.sequence}")
    else
      {:error, reason} -> DuetBridgeLogScript.halt_error(reason)
    end

  ["reset"] ->
    if System.get_env("CODEX_DUET_ENTRY") == "1" do
      DuetBridgeLogScript.halt_error("a Duet entry cannot reset the bridge log")
    end

    with {:ok, node} <- DuetBridgeLogScript.connect(),
         :ok <- DuetBridgeLogScript.call(node, :reset, []) do
      IO.puts("Bridge log reset")
    else
      {:error, reason} -> DuetBridgeLogScript.halt_error(reason)
    end

  _ ->
    DuetBridgeLogScript.halt_error(
      "Usage: bridge_log.exs <read | read-after SEQUENCE | publish BODY | reset>"
    )
end
