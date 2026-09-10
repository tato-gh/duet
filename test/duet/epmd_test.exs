defmodule Duet.EpmdTest do
  use ExUnit.Case, async: false

  setup do
    original_path = System.get_env("PATH")

    on_exit(fn -> restore_path(original_path) end)

    :ok
  end

  test "starts epmd in daemon mode" do
    bin_dir = fake_epmd(~s([ "$1" = "-daemon" ] || exit 3))
    System.put_env("PATH", bin_dir)

    assert :ok = Duet.Epmd.ensure_started()
  end

  test "returns a useful error when epmd is not installed" do
    System.put_env("PATH", System.tmp_dir!())

    assert {:error, "epmd executable was not found in PATH"} = Duet.Epmd.ensure_started()
  end

  test "includes command output when epmd fails to start" do
    bin_dir = fake_epmd("echo port-unavailable >&2\nexit 2")
    System.put_env("PATH", bin_dir)

    assert {:error, message} = Duet.Epmd.ensure_started()
    assert message == "epmd -daemon exited with status 2: port-unavailable"
  end

  defp fake_epmd(body) do
    bin_dir =
      Path.join(System.tmp_dir!(), "duet-epmd-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(bin_dir)
    executable = Path.join(bin_dir, "epmd")
    File.write!(executable, "#!/bin/sh\n#{body}\n")
    File.chmod!(executable, 0o755)
    bin_dir
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
