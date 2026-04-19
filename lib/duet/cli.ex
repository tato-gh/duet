defmodule Duet.CLI do
  @options []
  @usage_message "Usage: duet <path-to-DUETFLOW.md | project-dir>"

  def main(args) do
    :io.setopts(:user, encoding: :unicode)

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
      maybe_start_stdin_reader(config)
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to start: #{format_reason(reason)}"}
    end
  end

  defp start_node(node_name) do
    case Node.start(resolve_node_name(node_name), :shortnames) do
      {:ok, _} ->
        Node.set_cookie(:duet_cookie)
        :ok

      {:error, {:already_started, _}} ->
        Node.set_cookie(:duet_cookie)
        :ok

      {:error, reason} ->
        {:error, "Failed to start Erlang node: #{inspect(reason)}"}
    end
  end

  defp resolve_node_name(node_name) do
    if String.contains?(node_name, "@") do
      String.to_atom(node_name)
    else
      String.to_atom("#{node_name}@localhost")
    end
  end

  defp resolve_duetflow_path(input) do
    base_dir =
      case System.get_env("DUET_CALLER_CWD") do
        nil -> File.cwd!()
        "" -> File.cwd!()
        cwd -> cwd
      end

    expanded = Path.expand(input, base_dir)
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

  defp maybe_start_stdin_reader(%{diff_watch: %{enabled: true}}) do
    spawn_link(fn -> read_stdin() end)
    :ok
  end

  defp maybe_start_stdin_reader(_), do: :ok

  defp read_stdin do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        text = String.trim(line)

        cond do
          text == "/clear" ->
            Phoenix.PubSub.broadcast(Duet.PubSub, "duet:events", {:user_clear, %{}})

          text == "/compact" ->
            Phoenix.PubSub.broadcast(Duet.PubSub, "duet:events", {:user_compact, %{}})

          text != "" ->
            Phoenix.PubSub.broadcast(Duet.PubSub, "duet:events", {:user_message, %{text: text}})

          true ->
            :ok
        end

        read_stdin()
    end
  end
end
