defmodule Duet.EntryPrompts do
  @moduledoc false

  @timeout_avoidance_practice """
  もし完了の見通しが立たないリクエストを受けた場合は、まず全体像を把握し、ステップに分割した計画を提示したうえで、「1ステップずつ進めましょう」と相手に伝えてください。これはタイムアウト防止のためのプラクティスです。
  """

  def build_compact_summary_prompt do
    """
    現在の会話を新しいスレッドへ引き継ぐため、後続のAIエージェント向けの引き継ぎメモを作成してください。

    含める内容:
    - ユーザーの目的、制約、明示された好み
    - 決定済みの方針と、その理由
    - 作業の現状、変更済みのファイル、確認済みの事実
    - 未解決の課題、次に行うべきこと、注意点
    - 重要なコード、コマンド、エラー、参照情報

    憶測は事実と分けてください。不要な挨拶や前置きは避けてください。
    要約のみを出力し、それ以外のコメントは不要です。
    """
    |> String.trim()
  end

  def build_compact_handoff_prompt(summary) do
    """
    以下は前スレッドからの引き継ぎ情報です。
    これはユーザーからの新しい作業依頼ではなく、今後の応答で保持すべき会話文脈です。
    内容を把握したうえで、以後この前提を引き継いでください。

    <handoff>
    #{summary}
    </handoff>

    引き継ぎ内容を短く確認してください。
    """
    |> String.trim()
  end

  def build_turn_input(%{first_turn: true, role: role}, user_prompt) when role != "" do
    role_prompt = String.trim(role)
    practice = String.trim(@timeout_avoidance_practice)

    [
      %{
        type: "text",
        text: "あなたのroleは#{role_prompt}です。\n\n#{practice}\n\n#{user_prompt}"
      }
    ]
  end

  def build_turn_input(_state, user_prompt) do
    [%{type: "text", text: user_prompt}]
  end
end
