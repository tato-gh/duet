# Duet

Trial version.

## 概要

Duet は 2 つのモードで LLM app-server と連携します。

### Mode A: `diff_watch`（git diff 監視）

対象フォルダの `git diff` を監視し、変更検知ごとに LLM へ送って反応を生成します。

監視ループ:

1. `poll_interval` ごとに diff を取得
2. 前回の応答が完了していなければ次のポーリングまで待機（同時リクエストは送らない）
3. 前回 diff との差分（delta）を計算
4. delta を app-server に送って応答を生成
5. `Ctrl+C` まで繰り返し

スレッドコンテキスト再初期化:

- 起動時
- `DUETFLOW.md` のプロンプト変更時
- diff が空になった時

再初期化後、次に diff が発生したタイミングで「全 diff + プロンプト」を送信します。

### Mode B: `erpc_channel`（Erlang RPC）

AI エージェントから `erpc.call` 経由で Duet に問い合わせるための API を提供します。  
`erpc_channel` の各エントリは独立した app-server プロセスとスレッドコンテキストを持ちます。

## クイックスタート

### 前提条件

- [Codex CLI](https://github.com/openai/codex)（`codex app-server` が使えること）
- Elixir
- AI エージェント CLI（例: [Claude Code](https://github.com/anthropics/claude-code)）

### 1. Duet をビルド

```bash
git clone <duet-repo> ~/duet
cd ~/duet
mix setup
mix build
```

### 2. サンプルプロジェクト作成

```bash
mkdir ~/foo && cd ~/foo
git init
echo "# foo" > README.md
git add . && git commit -m "init"
```

### 3. 設定とスキルを配置

```bash
cp ~/duet/DUETFLOW.md.example ~/foo/DUETFLOW.md
mkdir -p ~/foo/.claude/skills
ln -s ~/duet/skill_duet.example ~/foo/.claude/skills/skill_duet
```

### 4. Duet 起動（別ターミナル）

```bash
~/duet/bin/duet ~/foo
```

`duet` の引数は以下のどちらでも指定できます。

- `DUETFLOW.md` のパス
- `DUETFLOW.md` を含むプロジェクトディレクトリ

### 5. 動作確認

`diff_watch`（Mode A）:

```bash
cd ~/foo
echo "hello!" >> README.md
```

Duet 側ターミナルに AI の応答が出れば成功です。

`erpc_channel`（Mode B）:

```bash
cd ~/foo
claude "duetを使って会話を数回して"
```

エージェントがスキル経由で Duet エントリに問い合わせます。

## 運用

- 停止: `Ctrl+C`
- 標準入力で `/clear` を送ると現在スレッドをクリア
- 標準入力に通常テキストを送ると、`diff_watch` モードに直接メッセージ送信

## Configuration

設定は監視対象ディレクトリの `DUETFLOW.md`（YAML front-matter）で行います。

- `DUETFLOW.md` が存在しない場合: デフォルト設定で起動
- `DUETFLOW.md` が存在する場合: YAML front-matter（`--- ... ---`）が必須

### app-server

現在対応している app-server は `codex app-server` のみです。  
`command` のデフォルト値も `codex app-server` です。

### YAML front-matter

トップレベル:

| キー | デフォルト | 説明 |
|------|-----------|------|
| `node_name` | `duet@<hostname>` | Duet の Erlang ノード名 |

`diff_watch`（Mode A）:

| キー | デフォルト | 説明 |
|------|-----------|------|
| `enabled` | `true` | Mode A の有効/無効 |
| `command` | `codex app-server` | app-server 起動コマンド |
| `diff_command` | `git diff HEAD` | diff 取得コマンド（`DUETFLOW.md` は常に除外） |
| `poll_interval` | `1000` | ポーリング間隔（ms） |
| `include_untracked` | `false` | untracked を diff に含めるか |
| `file_change_approval` | `reject` | ファイル変更承認ポリシー（`reject` / `acceptForSession`） |
| `prompt` | `""` | diff_watch 用システムプロンプト |

`erpc_channel`（Mode B）:

配列。各要素が独立した app-server プロセスを持ちます。

| キー | デフォルト | 説明 |
|------|-----------|------|
| `name` | 必須 | エントリ識別名（`erpc.call` で使用） |
| `enabled` | `true` | エントリ有効/無効 |
| `command` | `codex app-server` | app-server 起動コマンド |
| `role` | `""` | 初回ターン時に付与するロール文 |

サンプルは `DUETFLOW.md.example` を参照してください。

## 参考資料

- app-server プロトコル仕様: [`docs/codex-app-server-protocol.md`](docs/codex-app-server-protocol.md)
