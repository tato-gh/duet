defmodule Duet.DiffWatch.DiffSource do
  @moduledoc """
  git diff の取得とフィルタ処理を担当する。
  """

  @untracked_diff_command ~s(git ls-files --others --exclude-standard -- . | while IFS= read -r f; do git diff --no-index -- /dev/null "$f" 2>/dev/null; done)

  def run(diff_command, cwd, include_untracked) do
    {tracked, _} =
      System.cmd("sh", ["-c", diff_command <> " -- ."], cd: cwd, stderr_to_stdout: false)

    untracked =
      if include_untracked do
        {out, _} =
          System.cmd(
            "sh",
            ["-c", @untracked_diff_command],
            cd: cwd,
            stderr_to_stdout: false
          )

        out
      else
        ""
      end

    filter_duetflow(tracked <> untracked)
  end

  def filter_duetflow(diff_output) do
    {kept, _} =
      diff_output
      |> String.split("\n")
      |> Enum.reduce({[], false}, &filter_line/2)

    kept |> Enum.reverse() |> Enum.join("\n")
  end

  defp filter_line("diff --git" <> _ = line, {acc, _skip}) do
    skip = String.contains?(line, "DUETFLOW.md")
    {if(skip, do: acc, else: [line | acc]), skip}
  end

  defp filter_line(_line, {acc, true}), do: {acc, true}
  defp filter_line(line, {acc, false}), do: {[line | acc], false}
end
