defmodule Duet do
  @moduledoc false
end

defmodule Duet.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    path = Duet.Duetflow.duetflow_file_path()

    config =
      case Duet.Duetflow.parse(path) do
        {:ok, c} -> c
        {:error, reason} -> raise "Failed to parse DUETFLOW.md: #{reason}"
      end

    children =
      [
        {Phoenix.PubSub, name: Duet.PubSub},
        {Registry, keys: :unique, name: Duet.ErpcChannel.Registry},
        Duet.ConfigWatcher,
        Duet.ErpcChannel.Supervisor
      ] ++ diff_watch_children(config)

    result =
      Supervisor.start_link(
        children,
        strategy: :one_for_one,
        name: Duet.Supervisor
      )

    case result do
      {:ok, _pid} ->
        start_erpc_entries(config.erpc_channel)
        result

      error ->
        error
    end
  end

  @impl true
  def stop(_state), do: :ok

  defp diff_watch_children(%{diff_watch: %{enabled: true}}) do
    [Duet.DiffWatch.Supervisor]
  end

  defp diff_watch_children(_), do: []

  defp start_erpc_entries(entries) do
    Enum.each(entries, fn entry ->
      if entry.enabled do
        case Duet.ErpcChannel.Supervisor.start_entry(entry) do
          {:ok, _} ->
            Logger.info("ErpcChannel entry started: #{entry.name}")

          {:error, reason} ->
            Logger.error("Failed to start ErpcChannel entry #{entry.name}: #{inspect(reason)}")
        end
      end
    end)
  end
end
