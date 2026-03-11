defmodule Duet.CLI do
  @options [logs_root: :string]
  @usage_message "Usage: duet [--logs-root <path>] [path-to-DUETWORK.md]"

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
    args
    |> OptionParser.parse(strict: @options)
    |> case do
      {opts, [duetwork_path], []} ->
        run(duetwork_path)

      _ ->
        {:error, @usage_message}
    end
  end

  defp run(duetwork_path) do
    expanded_path = Path.expand(duetwork_path)

    with true <- File.regular?(expanded_path),
         :ok <- Duet.Duetwork.set_duetwork_file(expanded_path),
         {:ok, _started_apps} <- Application.ensure_all_started(:duet) do
      :ok
    else
      {:error, reason} ->
        {:error, "Failed to start Duet with #{expanded_path}: #{inspect(reason)}"}
      _error ->
        {:error, "Duetwork file not found or invalid: #{expanded_path}"}
    end
  end

  defp wait_for_shutdown do
    case Process.whereis(Duet.Supervisor) do
      nil ->
        IO.puts(:stderr, "Duet supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} ->
            System.halt(0)

          _ ->
            System.halt(1)
        end
    end
  end
end
