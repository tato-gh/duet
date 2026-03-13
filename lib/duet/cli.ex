defmodule Duet.CLI do
  @options [logs_root: :string]
  @usage_message "Usage: duet [--logs-root <path>] [path-to-DUETFLOW.md]"

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
      {_opts, [duetflow_path], []} -> run(duetflow_path)
      _ -> {:error, @usage_message}
    end
  end

  defp run(duetflow_path) do
    expanded_path = Path.expand(duetflow_path)
    Process.flag(:trap_exit, true)

    with true <- File.regular?(expanded_path),
         :ok <- Duet.Duetflow.set_duetflow_file(expanded_path),
         {:ok, _} <- Application.ensure_all_started(:phoenix_pubsub),
         {:ok, _pid} <- Duet.Application.start(:normal, []) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to start: #{format_reason(reason)}"}
      _error ->
        {:error, "DUETFLOW.md not found: #{expanded_path}"}
    end
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
end
