defmodule Duet.DiffWatch.Poller do
  @moduledoc """
  管理リソースは git diff の変動監視。
  設定変更の監視は Duet.ConfigWatcher が担う。
  """

  use GenServer
  require Logger
  alias Duet.DiffWatch.Delta
  alias Duet.DiffWatch.DiffSource

  @topic "duet:events"

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
    Phoenix.PubSub.subscribe(Duet.PubSub, @topic)
    config = Duet.ConfigWatcher.get_config().diff_watch
    duetflow_path = Duet.Duetflow.duetflow_file_path()
    schedule_poll(0)

    {:ok,
     %{
       duetflow_path: duetflow_path,
       config: config,
       prev_diff_hash: nil,
       prev_diff_empty: true,
       prev_diff: ""
     }}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = check_diff(state)
    schedule_poll(state.config.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:config_changed, %{config: new_config}}, state) do
    {:noreply, %{state | config: new_config}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp check_diff(state) do
    cwd = Path.dirname(state.duetflow_path)
    diff = DiffSource.run(state.config.diff_command, cwd, state.config.include_untracked)
    new_hash = :crypto.hash(:sha256, diff) |> Base.encode16()

    if new_hash == state.prev_diff_hash do
      state
    else
      new_empty = diff == ""

      cond do
        new_empty ->
          broadcast(:context_reset, %{prompt: state.config.prompt})

        state.prev_diff_empty ->
          broadcast(:diff_started, %{prompt: state.config.prompt, diff: diff})

        true ->
          delta = Delta.diff_delta(state.prev_diff, diff)
          if delta != "", do: broadcast(:diff_changed, %{diff: delta})
      end

      %{state | prev_diff_hash: new_hash, prev_diff_empty: new_empty, prev_diff: diff}
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Duet.PubSub, @topic, {event, payload})
  end
end
