defmodule Duet.CLI do
  @options [logs_root: :string]
  @usage_message "Usage: duet [--logs-root <path>] <path-to-DUETFLOW.md | project-dir>"

  def main(args) do
    case evaluate(args) do
      :ok ->
        wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  defp evaluate(args) do
    case OptionParser.parse(args, strict: @options) do
      {_opts, [path], []} -> run(path)
      _ -> {:error, @usage_message}
    end
  end

  defp run(path) do
    duetflow_path = resolve_duetflow_path(path)
    Process.flag(:trap_exit, true)

    with :ok <- Duet.Duetflow.set_duetflow_file(duetflow_path),
         {:ok, config} <- Duet.Duetflow.parse(duetflow_path),
         :ok <- start_node(config.node_name),
         {:ok, _} <- Application.ensure_all_started(:phoenix_pubsub),
         {:ok, _pid} <- Duet.Application.start(:normal, []) do
      spawn_link(fn -> read_stdin() end)
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to start: #{format_reason(reason)}"}
    end
  end

  defp start_node(node_name) do
    case Node.start(String.to_atom(node_name), :shortnames) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> {:error, "Failed to start Erlang node: #{inspect(reason)}"}
    end
  end

  defp resolve_duetflow_path(input) do
    expanded = Path.expand(input)
    if File.dir?(expanded), do: Path.join(expanded, "DUETFLOW.md"), else: expanded
  end

  defp format_reason({:shutdown, {:failed_to_start_child, _child, reason}}),
    do: format_reason(reason)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp wait_for_shutdown do
    case Process.whereis(Duet.Supervisor) do
      nil ->
        IO.puts(:stderr, "Duet supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)
        do_wait(ref, pid)
    end
  end

  defp do_wait(ref, pid) do
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} -> System.halt(0)
      {:DOWN, ^ref, :process, ^pid, _reason} -> System.halt(1)
      _other -> do_wait(ref, pid)
    end
  end

  defp read_stdin do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        text = String.trim(line)

        if text != "" do
          Phoenix.PubSub.broadcast(Duet.PubSub, "duet:events", {:user_message, %{text: text}})
        end

        read_stdin()
    end
  end
end
