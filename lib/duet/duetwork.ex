defmodule Duet.Duetwork do
  @moduledoc """
  Loads duetwork configuration and prompt from DUETWORK.md.
  """

  def duetwork_file_path do
    Application.get_env(:duet, :duetwork_file_path)
  end

  def set_duetwork_file(path) when is_binary(path) do
    Application.put_env(:duet, :duetwork_file_path, path)
    :ok
  end
end
