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

同フォルダの `entries.exs` を使う。

```bash
elixir --sname NAME@localhost entries.exs
# 例:
elixir --sname aiagent@localhost entries.exs
```

### 2. 単一エントリへの問い合わせ

同フォルダの `post.exs` を使う。

```bash
elixir --sname NAME@localhost post.exs ENTRY_NAME "PROMPT"
# 例:
elixir --sname aiagent@localhost post.exs review "このコードをレビューして"
```

### 3. 複数エントリへの並行問い合わせ

同フォルダの `post_parallel.exs` を使う。エントリ名とプロンプトを交互に並べる。

```bash
elixir --sname NAME@localhost post_parallel.exs ENTRY1 "PROMPT1" ENTRY2 "PROMPT2"
# 例:
elixir --sname aiagent@localhost post_parallel.exs review "コードをレビューして" summary "PRを要約して"
```

## エラー

| reason | 意味 | 対処 |
|--------|------|------|
| `:not_found` | エントリ名が存在しない | DUETFLOW.md のエントリ名を確認する |
| `:busy` | エントリが処理中 | 待ってリトライする |
| `"failed"` / `"interrupted"` | LLM 側でエラー | リトライする |
