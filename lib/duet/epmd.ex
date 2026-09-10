defmodule Duet.Epmd do
  @moduledoc false

  def ensure_started do
    case System.find_executable("epmd") do
      nil ->
        {:error, "epmd executable was not found in PATH"}

      executable ->
        start(executable)
    end
  end

  defp start(executable) do
    case System.cmd(executable, ["-daemon"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        detail = String.trim(output)
        suffix = if detail == "", do: "", else: ": #{detail}"
        {:error, "epmd -daemon exited with status #{status}#{suffix}"}
    end
  rescue
    error in ErlangError ->
      {:error, "could not run epmd -daemon: #{Exception.message(error)}"}
  end
end
