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

### 3. Duet を起動

別ターミナルで起動します。

```bash
~/duet/bin/duet.escript /path/to/project
```

引数には `DUET.md` のパス、または `DUET.md` を含むプロジェクトディレクトリを指定できます。

```bash
~/duet/bin/duet.escript /path/to/project/DUET.md
~/duet/bin/duet.escript /path/to/project
```

### 4. skill 経由で試す

プロジェクトディレクトリで、AI エージェントに自然文で依頼します。

```bash
cd /path/to/project
claude "duetを使って、しりとりを10ターン続けて"
```

エージェントが `skill-duet` 経由で起動中の Duet entry に問い合わせます。

`skill-duet-config` は任意です。AI エージェントに `DUET.md` の整理、entry の追加、role や権限設定の見直しを任せたいプロジェクトで配置します。

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

`DUET.md` がない場合、Duet は entry なしのデフォルト設定で起動します。

Duet は `DUET.md` を起動時にだけ読みます。ファイル変更の監視や hot reload はしないため、entry の追加・削除、role、`model`、`reasoning_effort`、`service_tier` の変更を反映するには Duet を再起動してください。

## 操作

- `/clear`: 選択した entry の thread を新しくする
- `/compact`: 現在の thread を要約し、新しい thread に引き継ぐ

## API

Duet は Erlang node として起動し、外部 node から `:erpc.call/5` で呼び出せます。

```elixir
Node.set_cookie(:duet_cookie)
Node.connect(:duet@localhost)

:erpc.call(:duet@localhost, Duet, :entries, [], 5_000)
:erpc.call(:duet@localhost, Duet, :post, ["work_partner", "相談したい内容"], 300_000)
```

- `Duet.entries/0` returns running entries as `%{name: name, role: role}`.
- `Duet.post/2` returns `{:ok, response}` or `{:error, reason}`.
