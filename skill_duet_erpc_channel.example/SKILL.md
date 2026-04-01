# Duet erpc_channel の使い方

Duet の erpc_channel モードを通じて、設定済みの AI エントリ（独立した LLM セッション）に
プロンプトを送信し、結果を受け取るスキル。

## エントリの概念

エントリ1つ = 独立した AI（独自のスレッドとコンテキストを持つ）。
同じエントリに連続して送ると会話が継続する。
別のテーマを扱うには別エントリを使う。
複数のエントリに同時に問い合わせるには、その数だけエントリが必要。

## 手順

### 1. 利用可能なエントリ確認

Duet に直接問い合わせて、エントリ名と役割（role）を取得する。

```bash
elixir -e "
  Node.connect(:'NODE_NAME')
  IO.inspect :erpc.call(:'NODE_NAME', Duet.ErpcChannel, :entries, [], 5_000)
"
# => [%{name: "review", role: "コードレビュアー"}, %{name: "summary", role: "要約担当"}]
```

ノード名が不明な場合はデフォルト `duet@HOSTNAME` を試す。

### 2. 単一エントリへの問い合わせ

同フォルダの `post.exs` を使う。

```bash
elixir post.exs NODE_NAME ENTRY_NAME "PROMPT"
# 例:
elixir post.exs duet@myhostname review "このコードをレビューして"
```

### 3. 複数エントリへの並行問い合わせ

同フォルダの `post_parallel.exs` を使う。エントリ名とプロンプトを交互に並べる。

```bash
elixir post_parallel.exs NODE_NAME ENTRY1 "PROMPT1" ENTRY2 "PROMPT2"
# 例:
elixir post_parallel.exs duet@myhostname review "コードをレビューして" summary "PRを要約して"
```

## エラー

| reason | 意味 | 対処 |
|--------|------|------|
| `:not_found` | エントリ名が存在しない | DUETFLOW.md のエントリ名を確認する |
| `:busy` | エントリが処理中 | 待ってリトライする |
| `"failed"` / `"interrupted"` | LLM 側でエラー | リトライする |
