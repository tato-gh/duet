# Bridge log

Use this reference before the first bridge log read or write.

bridge logは、bridge sideとplayerの直接会話を補助するDuet process-localの活動ログである。
コード、テスト、通常ドキュメント、会話の代わりにはしない。

eventはDuet processのメモリに時系列で保存され、Git repositoryとworking treeを変更しない。
Duetを終了または再起動するとeventと既読位置は失われる。

## event

各eventは次の情報を持つ。

- `sequence`: Duetが付ける単調増加番号
- `sender`: 発信主体。playerは`CODEX_DUET_ENTRY_NAME`、bridge sideは`bridge`
- `branch`: 発信時のbranch。detached HEADでは`detached@<commit>`
- `body`: 自由記述
- `inserted_at`: Duetが付ける発信時刻

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

既存の前提や経緯を繰り返さず、前回から変わったことだけを記録する。
詳細な調査結果、反復ログ、成果物の本文は、通常の成果物または直接会話へ残す。

## CLI

bridge sideとplayerは同じ`bridge_log.exs`を使う。
playerからの`read`と`publish`はDuetの再帰呼び出しではないため許可される。

未読eventを読み、呼び出したidentityの既読位置を進める:

```bash
elixir --sname NAME@localhost /path/to/.codex/skills/skill-duet-bridge/bridge_log.exs read
```

指定sequenceより後の全eventを、既読位置を変えずに読む:

```bash
elixir --sname NAME@localhost /path/to/.codex/skills/skill-duet-bridge/bridge_log.exs read-after 0
```

eventを発信する。senderとbranchはCLIが補う:

```bash
elixir --sname NAME@localhost /path/to/.codex/skills/skill-duet-bridge/bridge_log.exs publish 'テストを追加し、現在GREENです。'
```

`read`では自分が発信したeventを表示しないが、そのsequenceまで既読位置を進める。
再確認が必要な場合は`read-after`を使う。

## 更新を知らせる

bridge sideが応答を必要とする場合:

```text
$skill-duet-bridge

bridge logを更新しました。未読eventを確認し、自分に関係する情報があれば報告してください。
```

この依頼は`post.exs`または、idleなplayerからまとめて応答を得る`post_all.exs`で送る。
bridge logに情報があるだけでは、新しい作業の依頼や権限を意味しない。

応答を待たない通知には`cast_all.exs`を使える。
castでは応答がbridge sideへ返らないため、結果が必要ならplayerにbridge logへの`publish`を依頼し、bridge sideが後から`read`する。
publishはbridge sideを自動的にwake-upしない。

## resetと終了

bridge作業が長く続き、フェーズが切り替わるときは、必要な進捗、判断、未解決事項を通常の成果物またはleadへの報告へ要約する。
過去eventが不要になった場合に限り、bridge sideからlogをresetする。

```bash
elixir --sname NAME@localhost /path/to/.codex/skills/skill-duet-bridge/bridge_log.exs reset
```

playerはresetしない。
Duetを終了または再起動した場合は自動的に内容が失われるため、終了前に必要な情報を通常の成果物へ残す。
