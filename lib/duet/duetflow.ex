defmodule Duet.Duetflow do
  @moduledoc """
  Loads duetflow configuration and prompt from DUETFLOW.md.
  """

  def duetflow_file_path do
    Application.get_env(:duet, :duetflow_file_path)
  end

  def set_duetflow_file(path) when is_binary(path) do
    Application.put_env(:duet, :duetflow_file_path, path)
    :ok
  end
end
