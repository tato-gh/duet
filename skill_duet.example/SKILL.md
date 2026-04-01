---
name: duet
description: 「duetを使って」「duetで進めて」など、他のAIエントリ(LLMセッション)とやり取りするときに使う。あるいは第三者や他の視点を必要とするときに自律的に用いる。
---

# Duet とは

他のAI エントリ（LLM セッション）へプロンプトを送信し応答を受け取る仕組みである。

## エントリの概念

エントリ1つ = 独立したAI（独自のスレッドとコンテキストを持つ）。
同じProjectに属している。同じエントリに連続して送ると会話が継続する。

## 使い方

まず何よりも本スキルを読んだ直後に「利用可能なエントリ確認」を行うこと。

### 1. 利用可能なエントリ確認

`entries.exs` を使う。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/entries.exs
```

### 2. 単一エントリへの送受信

`post.exs` を使う。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post.exs ENTRY_NAME "PROMPT"
```

長文~複数行の場合は、ヒアドキュメントでプロンプトを送る：

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post.exs ENTRY_NAME "$(cat <<'EOF'
複数行のプロンプト
行2
行3
EOF
)"
```

### 3. 複数エントリへの並行送受信

`post_parallel.exs` を使う。エントリ名とプロンプトを交互に並べる。

```bash
elixir --sname NAME@localhost /path/to/skill_duet/post_parallel.exs ENTRY1 "PROMPT1" ENTRY2 "PROMPT2"
```

長文~複数行の場合は、ヒアドキュメントでプロンプトを送る：

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

## プラクティス

- コンテキスト(記憶)をリセットする場合には"/clear"と送信すること
- 用件が変わる場合は"/clear"を先に送ること

## エラー

| reason | 意味 | 対処 |
|--------|------|------|
| `:not_found` | エントリ名が存在しない | DUETFLOW.md のエントリ名を確認する |
| `:busy` | エントリが処理中 | 待ってリトライする |
| `"failed"` / `"interrupted"` | LLM 側でエラー | リトライする |
