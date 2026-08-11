defmodule Duet.TimeoutTest do
  use ExUnit.Case, async: false

  setup do
    original_env = System.get_env("DUET_TIMEOUT_MINUTES")
    original_timeout = Application.get_env(:duet, :request_timeout_ms)

    on_exit(fn ->
      restore_env("DUET_TIMEOUT_MINUTES", original_env)
      restore_application_env(:request_timeout_ms, original_timeout)
    end)

    :ok
  end

  test "uses a 20 minute default when the environment variable is unset" do
    System.delete_env("DUET_TIMEOUT_MINUTES")

    assert :ok = Duet.Timeout.configure_from_env()
    assert Duet.Timeout.request_timeout_ms() == :timer.minutes(20)
  end

  test "uses DUET_TIMEOUT_MINUTES as the request timeout" do
    System.put_env("DUET_TIMEOUT_MINUTES", "30")

    assert :ok = Duet.Timeout.configure_from_env()
    assert Duet.Timeout.request_timeout_ms() == :timer.minutes(30)
  end

  test "rejects an invalid DUET_TIMEOUT_MINUTES value" do
    System.put_env("DUET_TIMEOUT_MINUTES", "0")

    assert {:error, message} = Duet.Timeout.configure_from_env()
    assert message =~ "DUET_TIMEOUT_MINUTES must be a positive integer"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_application_env(key, nil), do: Application.delete_env(:duet, key)
  defp restore_application_env(key, value), do: Application.put_env(:duet, key, value)
end
