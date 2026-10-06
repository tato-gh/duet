# Duet

Duet は、名前付きの Codex / Claude Code セッションを常駐させ、AI エージェントから継続相談できるようにする Erlang RPC ブリッジです。

各 entry は独立した CLI プロセスと会話文脈を持ちます。同じ entry に続けて依頼すると、前回までの文脈を保ったまま会話できます。Codex は `codex app-server`、Claude Code は `claude -p` の双方向 `stream-json` を使います。

## 前提条件

- 使用する backend の CLI がインストール・認証済みであること（Codex: `codex app-server`、Claude Code: `claude`）
- Elixir
- AI エージェント CLI（例: Claude Code）

## クイックスタート

### 1. Duet をビルド

```bash
git clone <duet-repo> ~/duet
cd ~/duet
mix setup
mix build
```

### 2. プロジェクトに設定と skill を配置

```bash
cd /path/to/project
cp ~/duet/DUET.md.example ./DUET.md
mkdir -p .claude/skills
ln -s ~/duet/skill_examples/skill-duet .claude/skills/skill-duet
```

`DUET.md` の整理や entry 設定の見直しも AI エージェントに任せたい場合は、設定編集用 skill も配置します。

```bash
ln -s ~/duet/skill_examples/skill-duet-config .claude/skills/skill-duet-config
```

#### Codexでapprovalを省略する（任意）

CodexからDuetを利用すると、各操作でローカルErlang nodeへ接続するために`elixir --sname`を実行します。
このコマンドを毎回承認したくない場合は、Duetを利用するプロジェクトに`.codex/rules/duet.rules`を作り、次を記述します。

```starlark
prefix_rule(
    pattern = ["elixir", "--sname"],
    decision = "allow",
    justification = "Allow local Erlang node communication with Duet",
)
```

このruleはDuet付属スクリプトに限らず、`elixir --sname`で始まるコマンド全般を許可します。
信頼できるプロジェクトでのみ使用してください。

### 3. Duet を起動

別ターミナルで起動します。

Duetは起動時にErlangのノード探索に必要な`epmd`をデーモンとして自動起動します。

```bash
~/duet/bin/duet.escript /path/to/project
```

引数には `DUET.md` のパス、または `DUET.md` を含むプロジェクトディレクトリを指定できます。

```bash
~/duet/bin/duet.escript /path/to/project/DUET.md
~/duet/bin/duet.escript /path/to/project
```

entry 応答の待機時間はデフォルトで20分です。起動時に `DUET_TIMEOUT_MINUTES` を正の整数（分）で指定すると上書きできます。

```bash
DUET_TIMEOUT_MINUTES=30 ~/duet/bin/duet.escript /path/to/project
```

不正な値を指定した場合は起動に失敗します。環境変数の変更は、Duet を再起動して反映します。付属の skill スクリプトはこのサーバー側設定の完了まで待機するため、別の固定上限で先に終了しません。

### 4. skill 経由で試す

プロジェクトディレクトリで、AI エージェントに自然文で依頼します。

```bash
cd /path/to/project
claude "duetを使って、しりとりを10ターン続けて"
```

エージェントが `skill-duet` 経由で起動中の Duet entry に問い合わせます。

`skill-duet-config` は任意です。AI エージェントに `DUET.md` の整理、entry の追加、role や権限設定の見直しを任せたいプロジェクトで配置します。

## 協働の進め方を選ぶ

`skill_examples/` には、基本操作と設定編集に加えて、次の運用例があります。
orchestra系とbridgeは別々の運用であり、同じ作業に併用しません。orchestra系の2種類も管理単位に合わせて一方を選びます。

| skill | 使う場面 | メインAIの担当 |
| --- | --- | --- |
| [skill-duet-bridge](skill_examples/skill-duet-bridge/SKILL.md) | ユーザーと相談しながら、必要なplayerを都度選ぶ | 対話、判断材料の統合、直接作業または委譲 |
| [skill-duet-orchestra](skill_examples/skill-duet-orchestra/SKILL.md) | フェーズとticketを使って作業を進める | 進行と完了判定。実装・レビュー・記録はworker / reviewer / scribeへ委譲 |
| [skill-duet-release-orchestra](skill_examples/skill-duet-release-orchestra/SKILL.md) | release / ticketとquickfixを管理する | orchestraの役割分担に加え、releaseの区切りとユーザーによる漏れ候補の確認を管理 |

いずれも操作には`skill-duet`を使います。必要なentryと管理ファイルは、選んだskillの初期設定referenceを参照してください。

## 設定

設定はプロジェクトディレクトリの `DUET.md` に YAML front matter で書きます。

```yaml
---
node_name: "duet"
entries:
  - name: "chat_play"
    command: "codex app-server"
    role: "雑談・遊びの相手。気軽で自然な会話を続ける。"
    model: "gpt-5.6-luna"
    reasoning_effort: "high"
    service_tier: "fast"
    approval_policy: "never"
    thread_sandbox: "read-only"
    turn_sandbox_policy:
      type: "readOnly"
      networkAccess: false

  - name: "work_partner"
    command: "codex app-server"
    role: "作業伴走者。実装・設計を継続的に相談し、必要に応じて案・反証・統合で改善する。"
    # service_tier: "fast"
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: true

  - name: "claude_reviewer"
    backend: "claude"
    role: "設計・コードのレビュー担当。問題点と改善案を簡潔に説明する。"
    model: "sonnet"
    reasoning_effort: "high"
    permission_mode: "dontAsk"
    tools: ["Read", "Glob", "Grep"]
---
```

トップレベル:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `node_name` | `duet@localhost` | Duet の Erlang ノード名 |
| `entries` | `[]` | 起動する entry の配列 |

付属の操作スクリプトは依存ライブラリなしで接続先だけを読みます。
`node_name`はトップレベルに1行で書き、英数字・`_`・`.`・`@`・`-`を使ってください。
引用符なし、単一引用符、二重引用符、および空白に続く行末コメントに対応します。
Duet 本体の配布通信は `127.0.0.1` で待ち受け、同じホスト内から操作します。
省略時は本体と同じ`duet@localhost`です。YAMLのaliasや複数行scalarは操作スクリプトでは扱いません。

entry 共通:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `name` | 必須 | entry 名。skill や RPC 呼び出しで使う識別子 |
| `backend` | `codex` | `codex` または `claude`。同じ設定内で併用可能 |
| `command` | backend による | Codex: `codex app-server`。Claude: `claude`（実行ファイルやラッパーの変更用。必須引数は Duet が追加） |
| `role` | `""` | 会話の初回ターンだけに付与するロール文 |
| `model` | 未指定 | Codex の `thread/start`、Claude の `--model` に渡すモデル |
| `reasoning_effort` | 未指定 | Codex の `effort`、Claude の `--effort`。Claude は `low` / `medium` / `high` / `xhigh` / `max`（モデルによる対応差あり） |

Codex 専用:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `service_tier` | 未指定 | `thread/start` の `serviceTier`。例: `"fast"` |
| `approval_policy` | `"never"` | app-server に渡す approvalPolicy |
| `thread_sandbox` | `"read-only"` | `thread/start` に渡す sandbox |
| `turn_sandbox_policy` | `{"type":"readOnly","networkAccess":false}` | `turn/start` に渡す sandboxPolicy |

Claude 専用:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `permission_mode` | `"dontAsk"` | Claude の `--permission-mode`。`default` / `dontAsk` / `acceptEdits` / `plan` / `auto` / `bypassPermissions` |
| `tools` | `["Read", "Glob", "Grep"]` | 使用する組み込みツールの配列。`[]` は組み込みツールなし、`["default"]` は全組み込みツール |
| `allowed_tools` | `[]` | 自動承認するツール規則の配列。例: `["Bash(mix test *)"]` |

Claude entry に Codex 専用設定を指定すると起動時の設定エラーになります。
Claude 専用設定を Codex entry に指定した場合もエラーです。
Claude の未知のキー、不正な型・値、未知の backend は黙って無視せずエラーにします。
`backend` の省略時は Codex のため、既存の設定は変更不要です。

Claude の既定の組み込みツールは読み取り用途に限定していますが、これは Codex の OS sandbox と同じものではありません。
Claude 自身の認証・設定・CLAUDE.md・hooks・MCP の読込は CLI に従います。
編集用 entry では `permission_mode: "acceptEdits"` と `tools: ["Read", "Glob", "Grep", "Edit", "Write", "Bash"]` などを明示します。
`allowed_tools` は利用可能なツールへの承認規則であり、`tools` にない組み込みツールを追加しません。

Claude の起動時には `-p --input-format stream-json --output-format stream-json --verbose` と、
制御要求用の `--permission-prompt-tool stdio`、上記の設定に対応する引数を追加します。
`command` のラッパーは追加引数を CLI に渡してください。
Duet は stdin を開いたまま保ち、ターン間で同じプロセス・会話を再利用します。
Claude がセッション状態通知を提供する場合は、`result` と `idle` の両方を待って応答・次の予約処理へ進みます。
状態通知のない旧 CLI では `result` を完了として扱うため、バックグラウンド agent の継続処理までの完了は保証しません。
Claude の初期化エラー・初期化タイムアウト・初期化中の CLI 終了では、その entry を停止し、即時再起動しません。
正常な entry を巻き込む再起動ループを避けるためです。ログを確認して設定や認証を修正後、Duet を再起動してください。
プロトコルの参照先: [Claude CLI](https://code.claude.com/docs/en/cli-reference)、
[Anthropic Agent SDK の制御処理](https://github.com/anthropics/claude-agent-sdk-python/blob/main/src/claude_agent_sdk/_internal/query.py)。

Duetはentry processへ`CODEX_DUET_ENTRY=1`と`CODEX_DUET_ENTRY_NAME=<entry名>`を設定します。
`codex app-server` commandにはCodexの`shell_environment_policy.set`も自動で追加し、turn内のshell commandへ同じ値を渡します。
custom app-server commandを使う場合、tool実行環境までの伝播はそのcommand側で保証してください。

`DUET.md` がない場合、Duet は entry なしのデフォルト設定で起動します。

Duet は `DUET.md` と `DUET_TIMEOUT_MINUTES` を起動時にだけ読みます。ファイル変更の監視や hot reload はしないため、entry の追加・削除、role、`model`、`reasoning_effort`、`service_tier`、タイムアウト設定の変更を反映するには Duet を再起動してください。

Duetは非対話運用です。承認要求をユーザーへ転送する機能はなく、受信した承認要求は拒否します。
`approval_policy: "on-request"`などを指定しても、人間が承認できる運用にはなりません。
ユーザー入力要求には、入力を提供できない旨を返します。
Claude の `permission_mode: "default"` も人間への承認待ちにはなりません。
対話承認を期待しやすい設定では起動時に説明を表示します。必要なツールと自動承認規則を明示してください。

## 操作

起動ログの `ready (codex)` / `ready (claude)` は CLI の初期化完了を示します。
`ready` はモデル呼び出しの認証・利用枠まで検証した結果ではありません。
付属の `entries.exs --status` で backend、`starting` / `ready` / `busy` / `interrupt_unknown` /
`failed` / `unavailable`、予約件数、停止理由を確認できます。初期化失敗で停止した設定済み entry も表示します。
これはモデル呼び出しを伴わない内部状態の照会です。従来の `entries.exs` は起動中 entry の名前と role を表示します。

- `/clear`: 選択した entry の thread を新しくする
- `/compact`: 現在の thread を要約し、新しい thread に引き継ぐ
- `interrupt.exs ENTRY_NAME`: 実行中の turn だけを中断する。予約済みの依頼は維持する。

`post.exs` / `post_all.exs` で `/clear` が成功すると「会話をリセットしました。」と表示します。
RPC の戻り値は従来どおり `{:ok, ""}` です。操作スクリプトは主要なエラーに対処方法も表示します。

Claude でも同じ操作を使えます。`/clear` は Claude プロセスを起動し直して新しい会話を開始します。
`/compact` は旧会話で要約を作成し、起動し直した Claude の新しい会話へ引き継ぎます。
Claude 内蔵の `/compact` に処理を委譲するわけではありません。
Claude の割り込み応答がタイムアウトすると、割り込み呼び出しと実行中の `post` は
`{:error, :interrupt_timeout}` を返し、予約を保留します。遅れて応答・完了通知が届けば処理を再開します。
応答が戻らない場合は `/clear` で新しい会話へ切り替えて復旧できます。旧会話の文脈は失われますが、予約は維持します。
現在の終了処理は Port を閉じて CLI の stdin EOF による終了を促す方式です。
OS プロセスの終了確認や SIGTERM/SIGKILL による回収は未実装のため、CLI が EOF に応答しない場合は旧プロセスが残る可能性があります。

`DUET_TIMEOUT_MINUTES`は呼び出し側の応答待機時間であり、entryの作業時間の上限ではありません。
待機がタイムアウトしても、実行中のturnと予約済みの依頼は自動では中断されません。
停止が必要なら`interrupt.exs`を使い、再送前に変更ファイルや実行結果を確認してください。
タイムアウトは通常の`{:error, reason}`応答ではなく、呼び出しのexitとして伝わります。

## API

Duet は Erlang node として起動し、外部 node から `:erpc.call/5` で呼び出せます。

```elixir
Node.set_cookie(:duet_cookie)
Node.connect(:duet@localhost)

:erpc.call(:duet@localhost, Duet, :entries, [], 5_000)
:erpc.call(:duet@localhost, Duet, :post, ["work_partner", "相談したい内容"], :infinity)
:erpc.call(:duet@localhost, Duet, :interrupt, ["work_partner"], 5_000)
```

- `Duet.entries/0` returns running entries as `%{name: name, role: role}`.
- `Duet.statuses/0` returns configured and running entries as `%{name: name, role: role, backend: backend, status: status, queued: count, reason: reason}`. Stopped configured entries remain visible; unavailable queue counts are `nil`.
- `Duet.post/2` returns `{:ok, response}` or `{:error, reason}`.
- `Duet.interrupt/1` returns `:ok` when the app-server accepts an interruption request. The active `post/2` then returns `{:error, "interrupted"}`; queued prompts continue normally.
