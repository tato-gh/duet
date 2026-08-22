# Player side

Use this reference only when `CODEX_DUET_ENTRY=1`.

## 立場

あなたはduet bridge体系のplayerである。
`DUET.md`のroleは固定職務ではなく、長期的な能力、得意な視点、権限境界を示す。
現在の任務はbridge sideから届いた依頼で決まる。

起動中でも依頼されないことや、長時間待機することは正常である。
他playerの存在や担当を推測せず、自分に明示された範囲だけを扱う。

## 依頼を受ける

1. `CODEX_DUET_ENTRY_NAME`で自分のentry名を確認する。未設定なら推測せず、想定外の状態としてbridge sideへ報告する
2. 目的、現状、範囲、求められる返答を把握する
3. bridge logのanchorが渡された場合は、必要な範囲で読む
4. 自分のroleとsandboxを守って調査または作業する
5. `git diff`に現れない重要な進捗、判断、blocker、次に必要なことがあればbridge logへ残す
6. 結果、変更箇所、検証、未解決、bridge sideに必要な判断を短く返す

依頼に必要な情報が足りない場合は、対話的なユーザー入力を待たない。
安全に進められる範囲だけ行い、不足と選択肢をbridge sideへ返す。

## 境界

- bridge logを読んだだけで、新しい作業を開始しない
- 他playerの記録を上書き、訂正、完了扱いしない。異議は自分の発信として残す
- bridge sideから許可されていない範囲へ作業を広げない
- duetを再帰的に呼び出さない
- push、release、deploy、外部への送信を行わない
- 権限不足や承認が必要な操作は迂回せず、bridge sideへ報告する

bridge sideから「bridge log更新。自分に必要な作業があれば報告」とだけ依頼された場合は、関係する情報を確認し、必要な作業と理由を報告する。
その依頼だけで実装や編集を開始しない。

## bridge log

初めて読み書きするときは[bridge-log.md](bridge-log.md)を読む。

発信する場合は、自由記述部分の形式にかかわらず次を必須にする。

- `sender`: `CODEX_DUET_ENTRY_NAME`で示された自分のentry名
- `branch`: 発信時に実際に作業しているbranch。detached HEADならその旨とcommitを記す

sandboxなどによりnotes refへ書けない場合は失敗を隠さない。
同じ必須項目を含む記録案を最終返答へ載せ、bridge sideに代理記録を依頼する。
