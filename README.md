# Duet

Trial version.

## 概要

Duet は対象フォルダの git diff を監視し続け、変更を検知するたびに LLM（app-server）により反応を生成させます。

注意：
DuetはAIエージェントを起動するため、動作がDuetで完結しておらず、想定していない挙動を含みます。気軽な実行はできません。

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

## 使い方

```bash
mix setup
mix build

# プロジェクトディレクトリを渡す（DUETFLOW.md があれば使用、なければデフォルト設定で起動）
./bin/duet /path/to/gitpj

# または DUETFLOW.md を直接指定する
./bin/duet /path/to/gitpj/DUETFLOW.md
```

`Ctrl+C` でリアルタイム監視を停止します。

## Configuration

Duet の設定は、監視対象ディレクトリの `DUETFLOW.md` ファイルで行います。このファイルは YAML front-matter とプロンプト本文で構成されます。`DUETFLOW.md` がない場合はすべての項目がデフォルト値で動作します。

### app-server について

現在 Duet が対応している app-server は **`codex app-server`** のみです。`command` のデフォルト値も `codex app-server` です。事前に [Codex CLI](https://github.com/openai/codex) をインストールしてください。

### YAML front-matter

| キー | デフォルト | 説明 |
|------|-----------|------|
| `command` | `codex app-server` | app-server として起動するコマンド。差分を受け取り続ける常駐プロセスを指定する |
| `diff_command` | `git diff HEAD` | 変更検出に使うコマンド。`git diff`（unstaged のみ）や `git diff HEAD`（staged + unstaged）など用途に応じて変更可。DUETFLOW.md 自体の変更は除外される |
| `poll_interval` | `1000` | ポーリング間隔（ミリ秒） |

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

## 参考資料

- **app-server プロトコル仕様**: [`docs/codex-app-server-protocol.md`](docs/codex-app-server-protocol.md) — JSON-RPC 2.0 通信の詳細（手動テストも含む）

