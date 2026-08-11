defmodule Duet.Timeout do
  @moduledoc false

  @env_var "DUET_TIMEOUT_MINUTES"
  @default_timeout_minutes 20
  @default_timeout_ms :timer.minutes(@default_timeout_minutes)

  def configure_from_env do
    with {:ok, timeout_ms} <- timeout_from_minutes(System.get_env(@env_var)) do
      Application.put_env(:duet, :request_timeout_ms, timeout_ms)
      :ok
    end
  end

  def request_timeout_ms do
    Application.get_env(:duet, :request_timeout_ms, @default_timeout_ms)
  end

  defp timeout_from_minutes(nil), do: {:ok, @default_timeout_ms}

  defp timeout_from_minutes(value) do
    case Integer.parse(value) do
      {minutes, ""} when minutes > 0 ->
        {:ok, :timer.minutes(minutes)}

      _ ->
        {:error,
         "#{@env_var} must be a positive integer number of minutes, got: #{inspect(value)}"}
    end
  end
end
