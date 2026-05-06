---
name: duet_config
description: 「DUET.mdを更新して」「duet設定を整理して」「entryを追加して」「roleを見直して」など、プロジェクトの DUET.md をAIエージェントが読み、必要に応じて安全に編集するときに使う。既存方針を尊重し、軽微な整理は進め、方針変更や権限変更は確認する。
---

# duet_config

プロジェクトの `DUET.md` を、AIエージェントと人間の共有設定ガイドとして扱う。
`DUET.md` には Duet の起動設定だけでなく、そのプロジェクトでAIエージェントが作業するときの前提、entry の役割、権限、運用上の合意を残す。

この skill は `DUET.md` を厳密に固定するためではなく、作業を通じて設定を育てるために使う。
AIエージェントは既存の記述を尊重しつつ、次回以降の作業で迷いにくい形へ整理してよい。

## 使うタイミング

- ユーザーが `DUET.md` や duet 設定の作成、更新、整理を依頼したとき
- entry の追加、削除、名称変更、role の見直しを行うとき
- approval policy、sandbox、network access などの権限設定を確認するとき
- プロジェクト固有のAI運用ルールを `DUET.md` に残したいとき
- duet の使い方に関する合意や注意点を、次回以降のAIエージェントにも伝えたいとき

## 基本方針

- `DUET.md` 全体を読んでから編集する
- YAML front matter は Duet が読む機械設定として扱い、壊さない
- Markdown 本文は人間とAIエージェントの共有ガイドとして扱う
- 既存の方針、名称、役割、権限設定を尊重する
- 明らかな追記、重複整理、表現整理はAIエージェントが行ってよい
- 方針変更、権限変更、削除、責任範囲の変更はユーザーに確認する
- 曖昧な内容は断定せず、必要なら `未確定` や `要確認` として残す

## 編集してよい内容

- ユーザーと合意した作業ルールの追記
- entry の role を、実際の用途に合わせて分かりやすくする整理
- 重複した説明や古い補足の整理
- AIエージェントが迷いやすい判断基準の明文化
- duet の再起動が必要な変更であることの注意書き
- Markdown 本文への設定ガイド、運用メモ、利用例の追加

## 確認が必要な内容

- 既存 entry の削除、名称変更、用途変更
- `approval_policy`、`thread_sandbox`、`turn_sandbox_policy`、`networkAccess` の変更
- セキュリティ、権限、外部通信、デプロイ、秘密情報に関わるルール
- チーム全体の開発フローや責任分界に関わる変更
- 既存の合意を上書きする変更
- 複数の解釈があり、どれを採用するか判断が必要な内容

## 設定項目

`DUET.md` の YAML front matter は Duet の設定であり、entry ごとの値は `codex app-server` の `thread/start` と `turn/start` に渡される。
設定値を追加・変更するときは、まず既存の `DUET.md` とこの skill の設定表を優先する。
Codex CLI のバージョン差分が疑わしい場合は `codex app-server --help` と `codex app-server generate-ts` または `codex app-server generate-json-schema` で確認する。

| 項目 | 意味 | 設定値・編集方針 |
| --- | --- | --- |
| `node_name` | Duet の Erlang node 名 | 通常は `"duet"` または `duet@<hostname>`。変更すると接続先名に影響するため確認する |
| `entries` | 起動する entry の一覧 | entry 追加は用途が明確なら行ってよい。削除、名称変更、統合は確認する |
| `entries[].name` | entry の識別名 | 必須。skill や RPC 呼び出しで使うため、既存名の変更は確認する |
| `entries[].command` | app-server 起動コマンド | 通常は `"codex app-server"`。`--listen`、`--config`、`--enable` などを足す場合は影響範囲を確認する |
| `entries[].role` | entry の初回 turn に渡す役割説明 | 用途に合わせて整理してよい。長すぎる一般論より、任せたい振る舞いと判断基準を短く書く |
| `entries[].approval_policy` | `turn/start` などに渡す承認ポリシー | 代表値は `"never"`、`"on-request"`、`"on-failure"`、`"untrusted"`。権限運用に関わるため変更は確認する |
| `entries[].thread_sandbox` | `thread/start` に渡す sandbox mode | 代表値は `"read-only"`、`"workspace-write"`、`"danger-full-access"`。thread 作成時の権限に関わるため変更は確認する |
| `entries[].turn_sandbox_policy.type` | `turn/start` に渡す sandbox policy 種別 | 代表値は `"readOnly"`、`"workspaceWrite"`、`"dangerFullAccess"`。`"externalSandbox"` は外部 sandbox 前提なので、採用前に確認する |
| `entries[].turn_sandbox_policy.networkAccess` | turn 中のネットワーク可否 | `true` は外部通信を許す。調査や依存取得に便利だが、変更は確認する |
| `entries[].turn_sandbox_policy.writableRoots` | `workspaceWrite` で書き込み可能にする絶対パスの一覧 | ローカル絶対パスを含むため、共有される `DUET.md` や例にはデフォルトで書かない。sandbox レベルの書き込み制限が明示的に必要な private 設定でだけ追加する |
| `entries[].turn_sandbox_policy.excludeTmpdirEnvVar` | `workspaceWrite` で環境変数由来の tmpdir を書き込み対象から外すか | 最新 schema で見える詳細設定。必要性が明確な場合だけ使う |
| `entries[].turn_sandbox_policy.excludeSlashTmp` | `workspaceWrite` で `/tmp` を書き込み対象から外すか | 最新 schema で見える詳細設定。必要性が明確な場合だけ使う |

## 設定値の目安

- 相談専用 entry は `thread_sandbox: "read-only"` と `turn_sandbox_policy.type: "readOnly"` を基本にする
- 作業伴走 entry は `workspace-write` / `workspaceWrite` を使える。共有設定では `writableRoots` を省き、role と運用メモで意図する書き込み範囲を明示する
- `danger-full-access` / `dangerFullAccess` は強い権限なので、ユーザーが明示した場合以外は提案に留める
- `approval_policy: "never"` は非対話運用に向くが、危険な操作も承認できない。権限を広げる場合は sandbox 側で制限する
- `approval_policy: "on-request"` はAIエージェントが必要時に承認を求める運用に向く
- `approval_policy: "on-failure"` は失敗時だけ承認を求める挙動だが、Codex CLI では deprecated と表示される場合があるため、新規採用は慎重にする
- `approval_policy: "untrusted"` は信頼済みでない操作の承認を求める用途に使う
- Codex app-server は experimental なため、未知の値や新しい permission profile を `DUET.md` に入れる前に、現在の Codex CLI で使える値か確認する

## 編集手順

1. `DUET.md` を読む
2. YAML front matter と Markdown 本文の境界を確認する
3. 変更が軽微な整理か、方針・権限に関わる変更かを分類する
4. 軽微な整理は直接編集する
5. 判断が必要な変更は、短い選択肢を添えてユーザーに確認する
6. 編集後、何を変えたかと、再起動など必要な次の操作を簡潔に伝える

## 書き方

- 抽象的な一般論より、次回のAIエージェントが判断に使える記述を優先する
- entry の role は、その entry に任せたい振る舞いが分かる文にする
- 権限設定の理由は、必要に応じて短く補足する
- 古い情報かもしれない内容は、日付や確認状態を添える
- 長くなりすぎる場合は、重要な合意、entry の意図、運用注意点を優先する

## DUET.md の形

`DUET.md` は YAML front matter を持つ Markdown として扱う。
front matter には Duet が読む設定を置き、本文にはプロジェクト固有の説明や運用メモを置く。

```markdown
---
node_name: "duet"
entries:
  - name: "work_partner"
    command: "codex app-server"
    role: "作業伴走者。設計、実装、レビューを継続的に相談する。"
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: true
      excludeTmpdirEnvVar: false
      excludeSlashTmp: false
---

# DUET

## entry の使い分け

- `work_partner`: 作業中の相談、反証、レビューに使う

## 運用メモ

- entry の追加、削除、role 変更を反映するには Duet を再起動する
```
