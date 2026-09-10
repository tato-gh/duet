# Duet

Duet は、名前付きの LLM app-server セッションを常駐させ、AI エージェントから継続相談できるようにする Erlang RPC ブリッジです。

各 entry は独立した app-server プロセスと thread context を持ちます。同じ entry に続けて依頼すると、前回までの文脈を保ったまま会話できます。

## 前提条件

- `codex app-server` が使えること
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
---
```

トップレベル:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `node_name` | `duet@<hostname>` | Duet の Erlang ノード名 |
| `entries` | `[]` | 起動する entry の配列 |

付属の操作スクリプトは依存ライブラリなしで接続先だけを読みます。
`node_name`はトップレベルに1行で書き、英数字・`_`・`.`・`@`・`-`を使ってください。
引用符なし、単一引用符、二重引用符、および空白に続く行末コメントに対応します。
省略時は本体と同じ`duet@<hostname>`です。YAMLのaliasや複数行scalarは操作スクリプトでは扱いません。

entry:

| キー | デフォルト | 説明 |
| --- | --- | --- |
| `name` | 必須 | entry 名。skill や RPC 呼び出しで使う識別子 |
| `command` | `codex app-server` | app-server 起動コマンド |
| `role` | `""` | thread の初回ターンだけに付与するロール文 |
| `model` | 未指定 | `thread/start` に渡すモデル。例: `"gpt-5.6-luna"` |
| `reasoning_effort` | 未指定 | `turn/start` に渡す推論強度。例: `"high"` |
| `service_tier` | 未指定 | `thread/start` の `serviceTier`。例: `"fast"` |
| `approval_policy` | `"never"` | app-server に渡す approvalPolicy |
| `thread_sandbox` | `"read-only"` | `thread/start` に渡す sandbox |
| `turn_sandbox_policy` | `{"type":"readOnly","networkAccess":false}` | `turn/start` に渡す sandboxPolicy |

Duetはentry processへ`CODEX_DUET_ENTRY=1`と`CODEX_DUET_ENTRY_NAME=<entry名>`を設定します。
`codex app-server` commandにはCodexの`shell_environment_policy.set`も自動で追加し、turn内のshell commandへ同じ値を渡します。
custom app-server commandを使う場合、tool実行環境までの伝播はそのcommand側で保証してください。

`DUET.md` がない場合、Duet は entry なしのデフォルト設定で起動します。

Duet は `DUET.md` と `DUET_TIMEOUT_MINUTES` を起動時にだけ読みます。ファイル変更の監視や hot reload はしないため、entry の追加・削除、role、`model`、`reasoning_effort`、`service_tier`、タイムアウト設定の変更を反映するには Duet を再起動してください。

Duetは非対話運用です。承認要求をユーザーへ転送する機能はなく、受信した承認要求は拒否します。
`approval_policy: "on-request"`などを指定しても、人間が承認できる運用にはなりません。
ユーザー入力要求には、入力を提供できない旨を返します。

## 操作

- `/clear`: 選択した entry の thread を新しくする
- `/compact`: 現在の thread を要約し、新しい thread に引き継ぐ
- `interrupt.exs ENTRY_NAME`: 実行中の turn だけを中断する。予約済みの依頼は維持する。

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
- `Duet.post/2` returns `{:ok, response}` or `{:error, reason}`.
- `Duet.interrupt/1` returns `:ok` when the app-server accepts an interruption request. The active `post/2` then returns `{:error, "interrupted"}`; queued prompts continue normally.
