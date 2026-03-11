defmodule Duet do
  @moduledoc """
  """
end

defmodule Duet.Application do
  use Application

  @impl true
  def start(_type, _args) do
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
