---
name: skill-duet
description: 「duetを使って」「duetで～」「別視点で継続相談して」「同じ相手に続けて依頼して」「duet entryを止めて」など、起動中の duet entry (AI) を文脈が続く伴走相手として活用するときに使う。利用可能 entry を確認し、用途に応じて post、post_all、cast_all、overview、interrupt から会話・通知・文脈の再確認・中断をする。
---

# skill-duet

起動中のduet entryへ依頼し、同じ相手と文脈を保って会話・作業を続ける。
途中経過、迷い、仮説、雑談をそのまま渡してよい。相手の返答を材料にし、最終判断と統合は呼び出し側で行う。

依頼の組み立て方や相談の進め方に迷ったときだけ、[使い方と依頼例](references/usage.md)を読む。操作が決まっていれば、この本文だけで進められる。

## entryを確認・選択する

entry名が不明なとき、会話の初回、または`:not_found`が返ったときは`entries.exs`で利用可能なentryとroleを確認する。同じ相手との継続中は毎回確認しなくてよい。

- 用途に合うentryを名前とroleから選ぶ
- 同じ話題は同じentryへ、前回からの差分を渡す
- 無関係な話題へ移る場合は`/clear`するか、別entryを使う
- 長い会話を要約して引き継ぐ場合は`/compact`を送る
- 保持文脈が不明なentryと会話を再開する場合は`overview`で確認する

entryは`DUET.md`のあるプロジェクトディレクトリで動く。Codex のファイル操作は`approval_policy`、`thread_sandbox`、`turn_sandbox_policy`に従う。
Claude は`permission_mode`、`tools`、`allowed_tools`に従う。Claude のツール制限は Codex の OS sandbox と同じではない。
agy の操作可否は `mode` と CLI 側の権限設定に従う。
Duet は人間への承認要求を転送せず、対話承認が必要な要求を拒否する。

PJ内の情報はパスや対象diffを示して読ませ、本文を転載しない。会話で決まった未記録の制約や、前回からの変更だけ補う。
返答の扱いは依頼に合わせる。発想や反証は候補として、レビュー指摘は該当コードと根拠を確認して扱う。実装の完了は報告だけでなく差分と検証結果で確認する。判定では伴走中の同意や口調に引きずられず、目的・制約・根拠に照らして採否を決める。

`CODEX_DUET_ENTRY=1`はDuetから起動されたentryを示し、`CODEX_DUET_ENTRY_NAME`にentry名が入る。通常の`codex app-server`ではturnのshellにも伝播する。`entries.exs`以外の操作スクリプトは、再帰呼び出しを防ぐため`CODEX_DUET_ENTRY=1`なら終了する。迂回して呼び出さない。

## コマンドの実行

各スクリプトは同じディレクトリの`client.exs`を読むため、配置・コピーはskillディレクトリ単位で行う。
接続先は作業ディレクトリの`DUET.md`から読む。`node_name`はトップレベルの1行に英数字・`_`・`.`・`@`・`-`で書き、単一・二重引用符と行末コメントに対応する。省略時は`duet@localhost`を使う。

Codexのproject-localな`prefix_rule`で判定できるよう、各操作を単純な単一コマンドにする。

- 下の`NAME`は呼び出しごとに衝突しない具体的なcaller node名へ、スクリプトのpathは配置先の絶対pathへ置き換える
- prompt全体をshell-safeな単一引数として渡す。prompt内の単一引用符もescapeする
- command substitution、backtick、heredoc、pipe、redirect、環境変数展開、globを使わない
- `cd`と連結せず、実行toolの`workdir`に対象プロジェクトディレクトリを指定する

基本形:

```bash
elixir --sname NAME@localhost /absolute/path/to/skill-duet/entries.exs
elixir --sname NAME@localhost /absolute/path/to/skill-duet/post.exs ENTRY_NAME 'PROMPT'
```

以下も同じ`elixir --sname NAME@localhost`に、スクリプトの絶対pathと引数を続けて、1操作ずつ実行する。

| スクリプトと引数 | 用途と完了の意味 |
| --- | --- |
| `entries.exs` | 起動中entryの名前とroleを一覧する |
| `entries.exs --status` | 設定済み・起動中entryのbackend、状態、予約件数、停止理由を確認する。停止した設定済みentryも表示する |
| `post.exs ENTRY_NAME 'PROMPT'` | 1 entryの応答を待つ。処理中なら`busy` |
| `post_all.exs 'PROMPT'` | 全entryへ送り、応答を待つ。処理中のentryには送らず、個別に`busy`を返す |
| `cast_all.exs 'PROMPT'` | 全entryへの処理予約を確認して戻る。モデルの完了は待たず、応答は取得できない |
| `overview.exs ENTRY_NAME` | 1 entryに保持文脈を説明させる。処理中なら`busy` |
| `overview_all.exs` | 全entryのoverviewを取得する。処理中のentryは`busy` |
| `interrupt.exs ENTRY_NAME` | 実行中turnの中断を要求する。予約済みの依頼は維持する |

複数行のpromptも、単一引数のまま渡す:

```bash
elixir --sname NAME@localhost /absolute/path/to/skill-duet/post.exs ENTRY_NAME '複数行のプロンプト
行2
行3'
```

`cast_all`はブランチ変更など、回答を待たず次の処理へ反映させる通知に使う。予約は同じentry内で到着順に処理され、entry間では並行して進む。返答が必要な依頼には`post`または`post_all`を使う。

`overview`はentry自身がrole、現在も有効な経緯・文脈、明確な未完了事項を最大3項目で説明する。Duetの内部状態を直接照会する機能ではなく、回答はentryの保持文脈に基づく。

## 文脈の切り替えと中断

`/clear`と`/compact`は`post`のpromptとして送る。全entryが対象なら`post_all`を使い、`busy`で未送信のentryを確認する。

| 操作 | 結果 |
| --- | --- |
| `/clear` | 新しいthreadへ切り替える |
| `/compact` | 現在の会話の要約を作り、新しいthreadへ引き継ぐ |
| `interrupt.exs ENTRY_NAME` | 実行中turnを中断する。中断された`post`は`"interrupted"`を返し、予約済みの依頼は続けて実行される |

`post.exs` と `post_all.exs` は `/clear` 成功時に「会話をリセットしました。」と表示する。RPC の成功値は従来どおり `{:ok, ""}`。

`entries.exs --status` はモデルを呼ばず、Duet の内部状態を照会する。
`starting` は初期化中、`ready` は受付可能、`busy` は処理中、`interrupt_unknown` は割り込み成否未確認、
`failed` は停止理由あり、`unavailable` は状態取得不可を示す。`queued` は実行待ちの予約件数で、実行中の依頼を含まない。
`ready` は CLI の初期化完了を示す。実際のモデル呼び出し時に認証や利用枠のエラーが発生する可能性はある。

## 待機とエラー

`post`・`post_all`・`overview`・`overview_all`の応答待機時間は、Duet起動時の`DUET_TIMEOUT_MINUTES`で設定する。既定は20分で、変更には再起動が必要。

待機のタイムアウトは作業の中断ではない。entryのturnと予約は継続するため、同じ依頼を自動で再送しない。停止が必要なら`interrupt`を使い、再送前に変更ファイルや実行結果を確認する。単一entryの呼び出しでは、タイムアウトは通常のエラー応答ではなくRPC呼び出しの失敗として現れる。

| reason | 意味・対処 |
| --- | --- |
| `:not_found` | 起動中entryが見つからない。`entries.exs --status`で設定済みentryの停止・失敗も確認する |
| `:busy` | 初期化中または処理中。`entries.exs --status`で確認し、完了後に必要な依頼を再送する |
| `:not_running` | 実行中turnがなく、中断は不要 |
| `:not_interruptible` | turn ID取得前など。中断が必要なら少し待って再試行する |
| `"failed"` / `"interrupted"` | turnが失敗または中断された。途中の変更と継続の必要性を確認してから再依頼する |
| `{:rpc_error, error}` | app-serverのRPC error。内容を確認し、必要ならentryや依頼を見直す |
| `{:claude_error, error}` | Claude の処理エラー。内容と起動側ログから認証・利用枠・モデル設定を確認する |
| `:unsupported_slash_command` | agy entry へ `/clear`・`/compact` 以外の `/` で始まる prompt を送った。entry と会話は維持される。先頭の `/` を避けて送り直す |
| `{:agy_error, error}` | Antigravity CLI の処理エラー。内容と起動側ログから認証・利用枠・モデル設定を確認する |
| `:interrupt_timeout` | 割り込みの成否が未確認。自動再送せず状態とログを確認する。遅い応答で再開することがある。復旧しなければ `/clear`。旧会話は失われるが予約は維持する |
| `{:initialize_failed, error}` / `:initialize_timeout` | 初期化失敗。ログで認証・設定を確認し、修正後に Duet を再起動する |
| `{:port_exit, status}` | CLI が終了した。`entries.exs --status` と起動側ログを確認する |
| `:empty_compact_summary` | 要約が空のため compact 中止。元の会話は維持される |
