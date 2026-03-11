defmodule Duet do
  @moduledoc """
  """
end

defmodule Duet.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # 起動が必要なサーバと役割
    # - Orchestrator ポーリングからの全体統括
    # - Task.Supervisor 非同期タスク管理役（共通）
    children = [
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: Duet.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    :ok
  end
end
