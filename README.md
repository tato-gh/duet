# Duet

Trial version.

## 概要

Duet は 2 つのモードで LLM エージェントと連携します。

### Mode A: diff_watch（git diff 監視）

対象フォルダの git diff を監視し続け、変更を検知するたびに LLM（app-server）により反応を生成します。

**監視ループ：**

1. **Diff 検出**：`poll_interval` で指定した間隔ごとに対象フォルダの変更（diff）をポーリングして検知する
2. **LLM 応答確認**：前のリクエストに対する LLM 応答がまだ完了していないなら、このターンをスキップして次のポーリング間隔に進む（並列リクエストを送らない）
3. **Delta 計算**：前回ポーリング時の diff との差分（delta）を計算する。delta は今回新たに加わった変更のみを表す増分であり、そのまま LLM への送信内容となる
4. **LLM 反応生成**：app-server に delta を送信して反応を生成する
5. **繰り返し**：`Ctrl+C` で停止されるまでステップ 1〜4 を繰り返す

**コンテキスト再初期化：**

app-server は以下のタイミングで再初期化されます（全 diff + プロンプト本文を送信）：

- **起動時**：app-server を起動したとき
- **DUETFLOW.md 変更**：設定ファイルの内容が更新されたとき
- **Diff 空文字列**：git diff が空になったとき（ポーリングで自動検出）

### Mode B: erpc_channel（Erlang RPC）

Claude 等の AI エージェントがプログラム的に LLM と対話するための口を提供します。設定エントリごとに独立した app-server プロセスが起動し、`erpc.call` 経由でレスポンスを受け取れます。複数エントリを定義することで用途別（要約用、レビュー用など）に独立したコンテキストを持てます。

注意：
DuetはAIエージェントを起動するため、動作がDuetで完結しておらず、想定していない挙動を含みます。気軽な実行はできません。

## チュートリアル

### 前提条件

- [Codex CLI](https://github.com/openai/codex) インストール済み
- Elixir インストール済み
- AI エージェント CLI（[Claude Code](https://github.com/anthropics/claude-code) 推奨、Codex CLI も可）インストール済み

### 1. Duet をビルドする

```bash
git clone <duet-repo> ~/duet
cd ~/duet && mix setup && mix build
```

### 2. チュートリアル用プロジェクトを作成する

```bash
mkdir ~/foo && cd ~/foo
git init
echo "# foo" > README.md
git add . && git commit -m "init"
```

### 3. 設定とスキルをコピーする

```bash
cp ~/duet/DUETFLOW.md.example ~/foo/DUETFLOW.md
mkdir -p ~/foo/.claude/skills
ln -s ~/duet/skill_duet.example ~/foo/.claude/skills/skill_duet
```

### 4. Duet を起動する（別ターミナル）

```bash
~/duet/bin/duet ~/foo
```

### 5. 動作確認

**diff_watch（Mode A）：**

```bash
cd ~/foo && echo "hello!" >> README.md
```

Duet のターミナルに AI の反応が表示されれば成功。

**erpc_channel（Mode B）：**

```bash
cd ~/foo && claude "duetを使って会話を数回して"
```

Claude（または他の AI エージェント）がスキルを通じて Duet のエントリに問い合わせを行います。


---

## 停止方法

`Ctrl+C` でリアルタイム監視を停止します。

## Configuration

Duet の設定は、監視対象ディレクトリの `DUETFLOW.md` ファイルで行います。このファイルは YAML front-matter で構成されます。`DUETFLOW.md` がない場合はすべての項目がデフォルト値で動作します。

### app-server について

現在 Duet が対応している app-server は **`codex app-server`** のみです。`command` のデフォルト値も `codex app-server` です。事前に [Codex CLI](https://github.com/openai/codex) をインストールしてください。

### YAML front-matter

**トップレベル**

| キー | デフォルト | 説明 |
|------|-----------|------|
| `node_name` | `duet@<hostname>` | Duet が起動する Erlang ノード名。`erpc_channel` を使う場合はホスト名を合わせること |

**`diff_watch` セクション（Mode A）**

| キー | デフォルト | 説明 |
|------|-----------|------|
| `enabled` | `true` | Mode A の有効／無効 |
| `command` | `codex app-server` | app-server として起動するコマンド |
| `diff_command` | `git diff HEAD` | 変更検出に使うコマンド。DUETFLOW.md 自体の変更は除外される |
| `poll_interval` | `1000` | ポーリング間隔（ミリ秒） |
| `include_untracked` | `false` | untracked ファイルを diff 対象に含めるか |
| `file_change_approval` | `reject` | ファイル変更の承認ポリシー。`"reject"` または `"acceptForSession"` |
| `prompt` | （なし） | diff_watch モードのシステムプロンプト |

**`erpc_channel` セクション（Mode B）**

配列形式。各エントリが独立した app-server プロセスを持ちます。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `name` | 必須 | エントリを識別する名前。`erpc.call` で指定する |
| `enabled` | `true` | このエントリの有効／無効 |
| `command` | `codex app-server` | app-server として起動するコマンド |
| `role` | （なし） | このエントリの AI に与えるロール（システムプロンプト） |

### サンプル

`DUETFLOW.md.example` を参照してください。

## 参考資料

- **app-server プロトコル仕様**: [`docs/codex-app-server-protocol.md`](docs/codex-app-server-protocol.md) — JSON-RPC 2.0 通信の詳細（手動テストも含む）

