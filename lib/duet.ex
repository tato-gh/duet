defmodule Duet do
  @moduledoc """
  Public API used by remote Erlang callers.
  """

  @reservation_timeout 5_000
  @post_all_timeout_grace 1_000
  @overview_prompt """
  オーケストレータに向けて、この entry の overview を返してください。新しい作業依頼ではありません。
  確認できる事実だけを、最大 3 項目・各 1 文の箇条書きで簡潔に説明してください。

  - role
  - 現在も有効な経緯・保持している文脈の概要
  - 継続中または未完了の事項が明確にあるかどうか。ある場合に限り、その状況と未解決点

  分からないことは推測せず省略してください。ファイル変更や外部操作は行わないでください。
  """

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
  Returns configured and running entries with backend, status, queue length and reason.
  Status is :starting, :ready, :busy, :interrupt_unknown, :failed or :unavailable.
  Unlike entries/0, stopped configured entries remain visible.
  """
  def statuses do
    configured =
      case Registry.meta(Duet.EntryRegistry, :configured_entries) do
        {:ok, entries} -> entries
        :error -> []
      end

    (configured ++ entries())
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
    |> Task.async_stream(
      fn entry ->
        fallback = %{
          name: entry.name,
          role: entry.role,
          backend: Map.get(entry, :backend, :unknown),
          status: :unavailable,
          queued: nil,
          reason: nil
        }

        try do
          GenServer.call(entry_name(entry.name), :get_status, 1_000)
        catch
          :exit, _ ->
            case Registry.meta(Duet.EntryRegistry, {:entry_failure, entry.name}) do
              {:ok, failure} -> Map.merge(fallback, failure)
              :error -> fallback
            end
        end
      end,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.map(fn {:ok, status} -> status end)
  end

  @doc false
  def entry_status(state, backend) do
    status =
      case state.status do
        :idle -> :ready
        phase when phase in [:starting, :initializing, :session_ready] -> :starting
        :interrupt_unknown -> :interrupt_unknown
        _ -> :busy
      end

    %{
      name: state.name,
      role: state.role,
      backend: backend,
      status: status,
      queued: :queue.len(state.pending_posts),
      reason: nil
    }
  end

  @doc false
  def record_entry_failure(name, reason) do
    Registry.put_meta(Duet.EntryRegistry, {:entry_failure, name}, %{
      status: :failed,
      reason: reason
    })
  end

  @doc """
  Sends a prompt to a named entry.

  Returns `{:ok, response}` or `{:error, reason}`.
  A call timeout exits the caller; it does not interrupt the entry's turn or queue.
  """
  def post(entry_name, prompt) when is_binary(entry_name) and is_binary(prompt) do
    name = {:via, Registry, {Duet.EntryRegistry, entry_name}}

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(name, {:post, prompt}, Duet.Timeout.request_timeout_ms())
    end
  end

  @doc """
  Interrupts the currently running turn of a named entry.

  Returns `:ok` once the app-server accepts the interruption request. The interrupted
  `post/2` call then returns `{:error, "interrupted"}`. Reserved prompts remain queued.
  """
  def interrupt(entry_name) when is_binary(entry_name) do
    name = entry_name(entry_name)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(name, :interrupt, 5_000)
    end
  end

  @doc """
  Asks a named entry for a concise self-description of its role and current context.

  This is a regular `post/2`, so a busy entry returns `{:error, :busy}`.
  """
  def overview(entry_name) when is_binary(entry_name) do
    post(entry_name, @overview_prompt)
  end

  @doc """
  Sends a prompt to every running entry and waits for all responses.

  This is the broadcast equivalent of `post/2`: busy entries return `{:error, :busy}`.
  Results are returned as `{entry_name, result}` tuples, ordered by entry name.
  """
  def post_all(prompt) when is_binary(prompt) do
    names = entry_names()
    timeout = Duet.Timeout.request_timeout_ms()

    names
    |> Task.async_stream(
      fn name -> {name, post(name, prompt)} end,
      timeout: timeout + @post_all_timeout_grace,
      on_timeout: :kill_task,
      ordered: true,
      max_concurrency: max(length(names), 1)
    )
    |> Enum.zip(names)
    |> Enum.map(fn
      {{:ok, {name, result}}, _expected_name} -> {name, result}
      {{:exit, reason}, name} -> {name, {:error, reason}}
    end)
  end

  @doc """
  Asks every running entry for a concise self-description of its role and current context.

  This is the broadcast equivalent of `overview/1`. Busy entries return
  `{:error, :busy}`.
  """
  def overview_all do
    post_all(@overview_prompt)
  end

  @doc """
  Reserves processing of a prompt for every running entry without waiting for responses.

  Returns after each listed entry has accepted the reservation. It does not wait for
  the entry's model processing or response.
  """
  def cast_all(prompt) when is_binary(prompt) do
    names = entry_names()

    names
    |> Task.async_stream(
      fn name -> {name, reserve(name, prompt)} end,
      timeout: @reservation_timeout,
      on_timeout: :kill_task,
      ordered: true,
      max_concurrency: max(length(names), 1)
    )
    |> Enum.flat_map(fn
      {:ok, {entry_name, :ok}} -> [entry_name]
      _ -> []
    end)
    |> then(&{:ok, &1})
  end

  defp reserve(entry_name, prompt) do
    name = entry_name(entry_name)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(name, {:enqueue, prompt}, @reservation_timeout)
    end
  end

  defp entry_names do
    entries()
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp entry_name(entry_name) do
    {:via, Registry, {Duet.EntryRegistry, entry_name}}
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
      {Registry,
       keys: :unique, name: Duet.EntryRegistry, meta: [configured_entries: config.entries]},
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
          :ok

        {:error, reason} ->
          Duet.record_entry_failure(entry.name, reason)
          Logger.error("Failed to start Duet entry #{entry.name}: #{inspect(reason)}")
      end
    end)
  end
end
