defmodule Duet do
  @moduledoc """
  Public API used by remote Erlang callers.
  """

  @timeout 600_000

  @doc """
  Returns the currently running entries.

  Each entry is returned as `%{name: name, role: role}`.
  """
  def entries do
    Registry.select(Duet.EntryRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Task.async_stream(
      fn {name, pid} ->
        try do
          role = GenServer.call(pid, :get_role, 1_000)
          %{name: name, role: role}
        catch
          :exit, _ -> %{name: name, role: nil}
        end
      end,
      timeout: 1_500,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.flat_map(fn
      {:ok, entry} -> [entry]
      _ -> []
    end)
  end

  @doc """
  Sends a prompt to a named entry.

  Returns `{:ok, response}` or `{:error, reason}`.
  """
  def post(entry_name, prompt) when is_binary(entry_name) and is_binary(prompt) do
    name = {:via, Registry, {Duet.EntryRegistry, entry_name}}

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(name, {:post, prompt}, @timeout)
    end
  end
end

defmodule Duet.Application do
  @moduledoc false

  require Logger

  def start(_type, _args) do
    path = Duet.Config.config_file_path()

    config =
      case Duet.Config.parse(path) do
        {:ok, config} -> config
        {:error, reason} -> raise "Failed to parse DUET.md: #{reason}"
      end

    children = [
      {Registry, keys: :unique, name: Duet.EntryRegistry},
      Duet.EntrySupervisor
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: Duet.Supervisor)

    case result do
      {:ok, _pid} ->
        start_entries(config.entries)
        result

      error ->
        error
    end
  end

  defp start_entries(entries) do
    Enum.each(entries, fn entry ->
      case Duet.EntrySupervisor.start_entry(entry) do
        {:ok, _pid} ->
          Logger.info("Duet entry started: #{entry.name}")

        {:error, reason} ->
          Logger.error("Failed to start Duet entry #{entry.name}: #{inspect(reason)}")
      end
    end)
  end
end
