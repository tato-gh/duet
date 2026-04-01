defmodule Duet.DiffWatch.Delta do
  @moduledoc """
  前回との差分から増分 delta を計算する。
  """

  def diff_delta(prev_diff, new_diff) do
    prev_sections = parse_diff_sections(prev_diff)

    new_diff
    |> parse_diff_sections()
    |> Enum.flat_map(fn {file, content} ->
      prev_lines = MapSet.new(String.split(prev_sections[file] || "", "\n"))
      [_header | rest] = String.split(content, "\n")
      delta = Enum.reject(rest, &MapSet.member?(prev_lines, &1))

      has_content =
        Enum.any?(delta, &(String.starts_with?(&1, "+") and not String.starts_with?(&1, "+++")))

      if has_content, do: [file <> "\n" <> Enum.join(delta, "\n")], else: []
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  def parse_diff_sections(diff) do
    diff
    |> String.split(~r/(?=^diff --git )/m)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn section ->
      file = section |> String.split("\n") |> hd() |> String.trim()
      {file, section}
    end)
    |> Map.new()
  end
end
