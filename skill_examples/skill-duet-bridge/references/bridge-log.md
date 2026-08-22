# Bridge log

Use this reference before the first bridge log read or write.

bridge logは、bridge sideとplayerの直接会話を補助するローカル活動ログである。
コード、テスト、通常ドキュメント、会話の代わりにはしない。

## 保存場所

専用notes refを使う。

```text
refs/notes/duet-bridge-local
```

このrefは通常branchとは別であり、working treeや通常の`git diff`を変更しない。
`local`は用途を示す命名であり、Gitによるpush防止機能ではない。

bridge sideはbridge logを初めて使うとき、現在の`HEAD`を1つのlog anchorとして決める。
同じbridge作業中はbranchが変わってもanchorを変えず、完全なobject IDをplayerへの依頼に含める。

```bash
git rev-parse --verify HEAD
```

有効な`HEAD`がない場合はbridge logを初期化せず、直接会話だけを使う。

## 記録形式

本文は自由記述だが、各発信の先頭に`sender`と`branch`を必ず書く。

```text
---
sender: <bridgeまたはentry名>
branch: <branch名またはdetached@commit>

<自由記述>
```

`sender`はコマンド実行者ではなく、その情報を発信した主体を示す。
bridge sideがplayerを代理して書く場合も、playerのentry名を記す。

記録に向く内容:

- 現在の進捗と担当した範囲
- `git diff`だけでは分からない判断と理由
- 実行した検証と要点
- blocker、未解決、次に必要なこと
- 他playerが確認すると役立つ短い文脈

記録しない内容:

- secret、credential、個人情報
- diffから十分分かるコードの転記
- 長いコマンド出力やテストログ
- 永続的な仕様や重要判断の唯一の原本

## 読む・追記する

`<ANCHOR>`にはbridge sideが共有した完全なobject IDを使う。

```bash
git notes --ref=duet-bridge-local show <ANCHOR>
```

まだnoteがない場合、`show`が失敗しても空のlogとして扱う。

追記例:

```bash
git notes --ref=duet-bridge-local append -m "$(cat <<'EOF'
---
sender: work_generalist
branch: feat/example

認証失敗ケースのテストを追加した。
実装側で失敗を解消する必要がある。
EOF
)" <ANCHOR>
```

追記に失敗した場合、`-f`で既存noteを上書きしない。
発信内容を保持したままbridge sideへ失敗を報告し、必要なら代理記録を依頼する。

## 更新を知らせる

bridge sideが応答を必要とする場合:

```text
$skill-duet-bridge

bridge logを更新しました。anchor: <ANCHOR>
自分に関係する情報を確認し、必要な作業があれば作業開始前に報告してください。
```

この依頼は`post.exs`または、idleなplayerからまとめて応答を得る`post_all.exs`で送る。

応答を待たない通知には`cast_all.exs`を使える。
castでは応答がbridge sideへ返らないため、必要な結果はworktreeまたはbridge logへ残すよう明示する。

## push前と終了時

bridge logはremoteへpushしない。
bridge sideとplayerは`--mirror`、`refs/*`、`refs/notes/*`を含むpushを行わない。

push前に専用refがあることを確認し、push対象を通常branchへ明示的に限定する。

```bash
git for-each-ref --format='%(refname)' refs/notes/duet-bridge-local
```

bridge作業を終了するときは、必要な進捗、判断、検証が通常の成果物またはleadへの報告に残っていることを確認する。
その後、専用ref全体を削除する。

```bash
git update-ref -d refs/notes/duet-bridge-local
git for-each-ref --format='%(refname)' refs/notes/duet-bridge-local
```

note単位の`git notes remove`だけではnotes refの履歴が残るため、終了時の掃除には使わない。
ref削除後のbridge logは通常手順では取り出しにくくなるため、必要な情報の退避前に削除しない。
