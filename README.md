# Duet

## 仕組み

Duet は被対象プロジェクトの git diff を監視し続け、変更を検知するたびに LLM（app-server）に反応を生成させます。

### 監視ループ

1. **Diff 検出**：1秒ごとに被対象フォルダの変更（diff）をポーリングして検知する
2. **Delta 計算**：前回ポーリング時の diff との差分（delta）を計算する。delta は今回新たに加わった変更のみを表す増分であり、そのまま LLM への送信内容となる
3. **LLM 反応生成**：app-server に delta を送信して反応を生成する
4. **繰り返し**：`Ctrl+C` で停止されるまでステップ 1〜3 を繰り返す

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

### サンプル

```markdown
---
command: codex app-server
diff_command: git diff HEAD
---

あなたはペアプログラマーです。
簡潔にコメントしてください。
```

