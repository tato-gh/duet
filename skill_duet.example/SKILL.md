---
name: duet
description: "独立 AI エントリに問い合わせる仕組み"
---

# Duet erpc_channel の使い方

Duet の erpc_channel モードを通じて、設定済みの AI エントリ（独立した LLM セッション）に
プロンプトを送信し、結果を受け取るスキル。

## エントリの概念

エントリ1つ = 独立した AI（独自のスレッドとコンテキストを持つ）。
同じエントリに連続して送ると会話が継続する。

## 手順

### 1. 利用可能なエントリ確認

同フォルダの `entries.exs` を使う。絶対パスで直指定できる。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/entries.exs
```

### 2. 単一エントリへの問い合わせ

同フォルダの `post.exs` を使う。絶対パスで直指定できる。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post.exs ENTRY_NAME "PROMPT"
```

ヒアドキュメントで複数行プロンプトも指定可能：

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post.exs ENTRY_NAME "$(cat <<'EOF'
複数行のプロンプト
行2
行3
EOF
)"
```

### 3. 複数エントリへの並行問い合わせ

同フォルダの `post_parallel.exs` を使う。エントリ名とプロンプトを交互に並べる。絶対パスで直指定できる。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post_parallel.exs ENTRY1 "PROMPT1" ENTRY2 "PROMPT2"
```

改行とヒアドキュメントで、複数行プロンプトを読みやすく指定可能：

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post_parallel.exs \
  entry1 "$(cat <<'EOF'
プロンプト1
複数行
EOF
)" \
  entry2 "$(cat <<'EOF'
プロンプト2
複数行
EOF
)"
```

## エラー

| reason | 意味 | 対処 |
|--------|------|------|
| `:not_found` | エントリ名が存在しない | DUETFLOW.md のエントリ名を確認する |
| `:busy` | エントリが処理中 | 待ってリトライする |
| `"failed"` / `"interrupted"` | LLM 側でエラー | リトライする |
