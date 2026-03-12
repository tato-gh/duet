# Duet

WIP

## 概要

Duet は被対象プロジェクトの git diff を監視し続け、変更を検知するたびに LLM（app-server）に反応を生成させます。

### 監視ループ

1. **Diff 検出**：`poll_interval` で指定した間隔ごとに被対象フォルダの変更（diff）をポーリングして検知する
2. **LLM 応答確認**：前のリクエストに対する LLM 応答がまだ完了していないなら、このターンをスキップして次のポーリング間隔に進む（並列リクエストを送らない）
3. **Delta 計算**：前回ポーリング時の diff との差分（delta）を計算する。delta は今回新たに加わった変更のみを表す増分であり、そのまま LLM への送信内容となる
4. **LLM 反応生成**：app-server に delta を送信して反応を生成する
5. **繰り返し**：`Ctrl+C` で停止されるまでステップ 1〜4 を繰り返す

### コンテキスト再初期化

app-server は以下のタイミングで再初期化されます（全 diff + プロンプト本文を送信）：

- **起動時**：app-server を起動したとき
- **DUETFLOW.md 変更**：設定ファイルの内容が更新されたとき
- **Diff 空文字列**：git diff が空になったとき（ポーリングで自動検出）

これにより新しいコンテキストで LLM との対話が継続します。

### 終了

- `Ctrl+C` でリアルタイム監視を停止します

## 使い方

```
mix setup
mix build
./bin/duet /path/to/gitpj/DUETFLOW.md
```

## Configuration

Duet の設定は、監視対象ディレクトリの `DUETFLOW.md` ファイルで行います。このファイルは YAML front-matter とプロンプト本文で構成されます。

### YAML front-matter

| キー | デフォルト | 説明 |
|------|-----------|------|
| `command` | （必須）| app-server として起動するコマンド。差分を受け取り続ける常駐プロセスを指定する |
| `diff_command` | `git diff HEAD` | 変更検出に使うコマンド。`git diff`（unstaged のみ）や `git diff HEAD`（staged + unstaged）など用途に応じて変更可。DUETFLOW.md 自体の変更は除外される（設定変更の検知は別途行われる） |
| `poll_interval` | `1000` | ポーリング間隔（ミリ秒）。デフォルトは 1000（1秒） |

### サンプル

```markdown
---
command: codex app-server
diff_command: git diff HEAD
poll_interval: 1000
---

あなたはペアプログラマーです。
簡潔にコメントしてください。
```

## Tips: codex app-server プロトコル仕様

`command` で指定するプロセスは **JSON-RPC 2.0 over stdio（JSONL形式）** で通信します。
以下は `codex app-server` を使う場合の仕様です。

### 通信フォーマット

- 1 メッセージ = 1 JSON オブジェクト + 改行（`\n`）
- リクエストは `id` を持ち、レスポンスは同じ `id` で返る
- 通知（notification）は `id` なし

### 起動シーケンス

```
Client                          Server
  |                               |
  |-- initialize (id=1) -------->|  clientInfo + capabilities
  |<-- result (id=1) ------------|  serverInfo など
  |-- initialized (通知) ------->|  id なし
  |-- thread/start (id=2) ------>|  cwd, approvalPolicy など
  |<-- result (id=2) ------------|  { thread: { id: "<thread_id>" } }
  |
  |  ↑ セッション確立。以降はターンを繰り返す
  |
  |-- turn/start (id=3) -------->|  threadId + input
  |<-- result (id=3) ------------|  { turn: { id: "<turn_id>" } }
  |<-- (通知ストリーム) ----------|  tool calls, approvals など
  |<-- turn/completed (通知) ----|  ターン完了
```

### 主なメッセージ

#### initialize

```json
{
  "method": "initialize",
  "id": 1,
  "params": {
    "capabilities": { "experimentalApi": true },
    "clientInfo": {
      "name": "my-client",
      "title": "My Client",
      "version": "1.0.0"
    }
  }
}
```

#### initialized（通知）

```json
{ "method": "initialized", "params": {} }
```

#### thread/start

```json
{
  "method": "thread/start",
  "id": 2,
  "params": {
    "approvalPolicy": "never",
    "sandbox": "none",
    "cwd": "/path/to/workspace"
  }
}
```

`approvalPolicy` の主な値：
- `"never"` — すべて自動承認（非インタラクティブ実行向け）
- `"untrusted"` — 信頼されていないコマンドのみ承認を求める

#### turn/start

```json
{
  "method": "turn/start",
  "id": 3,
  "params": {
    "threadId": "<thread_id>",
    "input": [{ "type": "text", "text": "差分内容をここに入れる" }],
    "cwd": "/path/to/workspace",
    "approvalPolicy": "never"
  }
}
```

### ターン中の通知（Server → Client）

| method | 意味 |
|--------|------|
| `turn/started` | ターン開始（`turn/start` レスポンス直後に届く） |
| `turn/completed` | ターン正常完了。`status: "completed"` を確認して次の送信が可能になる |
| `turn/failed` | ターン失敗 |
| `turn/cancelled` | ターンキャンセル |
| `item/started` | アイテム処理開始（UserMessage / Reasoning / AgentMessage など） |
| `item/completed` | アイテム処理完了。AgentMessage の場合 `item.text` に完全テキストが入る |
| `item/agentMessage/delta` | AgentMessage のストリーミングデルタ。`params.delta` に断片テキスト |
| `thread/tokenUsage/updated` | トークン使用量更新 |
| `item/tool/call` | クライアントへのツール呼び出し要求（要レスポンス） |
| `item/commandExecution/requestApproval` | コマンド実行承認要求 |
| `item/fileChange/requestApproval` | ファイル変更承認要求 |
| `item/tool/requestUserInput` | ユーザー入力要求 |

> **注**: `codex/event/*` 系通知は上記の公開 API 通知と同内容が重複して流れる。Duet では `item/*` / `turn/*` / `thread/*` 系のみを使えばよい。

承認要求へのレスポンス例：

```json
{ "id": "<request_id>", "result": { "decision": "acceptForSession" } }
```

### スレッドとターンの関係

- **スレッド（thread）**：セッション単位。プロセス起動ごとに 1 つ作成。
- **ターン（turn）**：LLM への 1 回の送信単位。スレッド内で複数回繰り返す。
- 前のターンが完了するまで次の `turn/start` を送らないこと（並列不可）。

### ID の種類と役割

| フィールド | 採番者 | 役割 |
|-----------|--------|------|
| JSON-RPC `id`（例: `3`） | クライアント | リクエスト↔レスポンスの 1:1 対応付け。通知には含まれない |
| `threadId`（UUID） | サーバー | スレッド識別子。`thread/start` の result から取得し、以降の `turn/start` に渡す |
| `turnId`（`"0"`, `"1"`, ...） | サーバー | スレッド内ターン連番。サーバーが自動採番。送信側は関与しない |
| `itemId`（UUID） | サーバー | アイテム識別子。`item/agentMessage/delta` のデルタ紐付けに使われる |

送信側が管理するのは **JSON-RPC `id`** と **`threadId`**（受け取って保持するだけ）のみ。

### リクエスト id の扱い

JSON-RPC の `id` はリクエストとレスポンスを 1 対 1 で対応づけるためのもの。グローバルなカウンターではない。

並列リクエストを送らない設計であれば、同じ id を再利用してよい。
例えば `turn/start` は何度送っても常に同じ id（例: `3`）で問題ない。
レスポンスを受け取った時点でその id との対応は完了しているため。

### sandbox と approvalPolicy

`codex app-server` は LLM がコマンド実行・ファイル変更などを行うため、
プロンプト内容に関わらずサンドボックス設定が実際の制限を決める。

#### approvalPolicy

| 値 | 動作 |
|----|------|
| `"never"` | 全操作を自動承認。ユーザーへのエスカレーションなし |
| `"onFailure"` | 失敗時のみユーザーへ確認（リトライを許可） |
| `"unlessTrusted"` | 信頼されていない操作のみ承認を求める |
| `"onRequest"` | LLM 自身が判断して承認を求める |

#### sandbox（SandboxMode / SandboxPolicy）

スキーマには v1（kebab-case 文字列）と v2（camelCase オブジェクト）の 2 形式が存在する。
実際に受け付けるのは起動した codex のバージョンに依存する。

| 値 | 動作 |
|----|------|
| `"danger-full-access"` / `"dangerFullAccess"` | 制限なし。cwd 外でも何でも可。**非推奨** |
| `"workspace-write"` / `"workspaceWrite"` | cwd（+ TMPDIR）のみ書き込み可。cwd 外への書き込みは禁止 |
| `"read-only"` / `"readOnly"` | 読み取り専用。コマンド実行・ファイル変更不可 |

`workspaceWrite` は追加オプションあり：

```json
{
  "type": "workspaceWrite",
  "writableRoots": ["/additional/path"],
  "networkAccess": false,
  "excludeTmpdirEnvVar": false
}
```

#### Duet での設定

Duet は差分への反応生成が目的のため、LLM がファイルを書き換えると git diff に混入して意図しない自己ループが生じる。

最小構成では `readOnly` + `approvalPolicy: "never"` で動かす。
cwd は DUETFLOW.md が置かれているフォルダに固定される。

```json
{
  "approvalPolicy": "never",
  "sandbox": { "type": "readOnly" }
}
```

### 手動テスト方法

```bash
mkfifo /tmp/codex_in
codex app-server < /tmp/codex_in &
exec 3>/tmp/codex_in

# initialize
printf '{"method":"initialize","id":1,"params":{"capabilities":{"experimentalApi":true},"clientInfo":{"name":"test","title":"Test","version":"1.0"}}}\n' >&3

# initialized
printf '{"method":"initialized","params":{}}\n' >&3

# thread/start
printf '{"method":"thread/start","id":2,"params":{"approvalPolicy":"never","sandbox":"readOnly","cwd":"/tmp"}}\n' >&3

# threadIdを使ってturn/startを送信
printf '{"method":"turn/start","id":3,"params":{"threadId":"todo","input":[{"type":"text","text":"Hello app!"}]}}\n' >&3

# 後片付け
exec 3>&-
rm /tmp/codex_in
```

