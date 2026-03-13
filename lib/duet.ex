defmodule Duet do
  @moduledoc false
end

defmodule Duet.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Duet.PubSubは肝のためone_for_allで起動
    # （通常は過度、練習用コード）
    children = [
      {Phoenix.PubSub, name: Duet.PubSub},
      Duet.ServiceSupervisor
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_all,
      name: Duet.Supervisor
    )
  end

  @impl true
  def stop(_state) do
    :ok
  end
end

defmodule Duet.ServiceSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Duet.Poller,
      Duet.AIClient
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
