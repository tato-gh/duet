defmodule Duet.ConfigWatcher do
  @moduledoc """
  管理リソースは DUETFLOW.md の設定変更監視（グローバル）
  """

  use GenServer
  require Logger

  @topic "duet:events"
  @poll_interval 1000

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    path = Duet.Duetflow.duetflow_file_path()
    mtime = read_mtime(path)

    case Duet.Duetflow.parse(path) do
      {:ok, config} ->
        schedule_poll()
        {:ok, %{path: path, mtime: mtime, config: config}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = check_config(state)
    schedule_poll()
    {:noreply, state}
  end

  # --- Private ---

  defp check_config(state) do
    new_mtime = read_mtime(state.path)

    if new_mtime == state.mtime do
      state
    else
      case Duet.Duetflow.parse(state.path) do
        {:error, reason} ->
          Logger.warning("Failed to reload DUETFLOW.md: #{reason}")
          %{state | mtime: new_mtime}

        {:ok, new_config} ->
          broadcast_changes(state.config, new_config)
          %{state | config: new_config, mtime: new_mtime}
      end
    end
  end

  defp broadcast_changes(old, new) do
    old_dw = old.diff_watch
    new_dw = new.diff_watch

    if old_dw.enabled != new_dw.enabled or
         old_dw.command != new_dw.command or
         old_dw.diff_command != new_dw.diff_command or
         old_dw.poll_interval != new_dw.poll_interval or
         old_dw.include_untracked != new_dw.include_untracked or
         old_dw.approval_policy != new_dw.approval_policy or
         old_dw.thread_sandbox != new_dw.thread_sandbox or
         old_dw.turn_sandbox_policy != new_dw.turn_sandbox_policy do
      broadcast(:config_changed, %{config: new_dw})
    end

    if old_dw.prompt != new_dw.prompt do
      broadcast(:prompt_changed, %{prompt: new_dw.prompt})
    end

    if old.erpc_channel != new.erpc_channel do
      broadcast(:erpc_config_changed, %{entries: new.erpc_channel})
    end
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp read_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Duet.PubSub, @topic, {event, payload})
  end
end
