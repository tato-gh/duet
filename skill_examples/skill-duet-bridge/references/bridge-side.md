# Bridge side

Use this reference only when `CODEX_DUET_ENTRY` is not `1`.

## 役割

partnerはleadとの対話と統合を中心に置く。
自律的なプロジェクト管理者としてleadから離れず、論点、判断材料、playerの結果、次の選択を短く共有し、leadが判断に参加できる状態を保つ。

partnerが作業を直接実行するかplayerへ依頼するかは固定せず、作業の独立性、所要時間、消費する文脈、並列化の価値、利用可能なplayerの能力と状態から都度選ぶ。
独立して委ねられる継続的な調査、実装、検証はplayerを優先する。
短い確認、結果の統合と不可分な作業、委譲コストの方が大きい作業はpartnerが直接行ってよい。
playerへの委譲自体を目的にしない一方、慣性で直接実行を選ばず、rosterを実質的な選択肢として評価する。

## 始める

1. leadの目的、現在の状態、判断が必要な点を把握する
2. 成果物作成、まとまった調査、実装、検証を進めるときは、`skill-duet`の`entries.exs`で起動済みentryとroleを確認する
3. 久しぶりに使うplayerや保持文脈が不明なplayerは、依頼前に`overview.exs`で確認する
4. role、保持文脈、model、reasoning、権限、応答時間から、目的に適したplayerまたはplayerの組み合わせを選ぶ。人数の少なさ自体を目的にしない
5. 適切なplayerがいなければ、roster変更を仮定せずleadへ伝える

全playerへの挨拶、初期化、均等な仕事配分は不要である。
起動済みでも、現在必要のないplayerには依頼しなくてよい。

## playerへ依頼する

単一playerとの直接会話を基本にする。
player側にもこのskillを明示的に読み込ませるため、最初の行に`$skill-duet-bridge`を書く。

```text
$skill-duet-bridge

目的: <今回達成したいこと>
現状: <必要な差分だけ>
範囲: <触ってよい範囲、避ける範囲>
返答: <必要な成果、判断、検証>
```

項目を埋めること自体を目的にせず、既存文脈があれば差分だけを渡す。
bridge logを使っている場合は、anchorと「読むだけか、必要な記録も行うか」を依頼に含める。

同じ問いを複数playerへ送り、全応答を比較するときは`post_all.exs`を使える。
busyなplayerには届かないため、全員の参加を前提にしない。
broadcastの先頭にも`$skill-duet-bridge`を書く。

状態通知を各playerの次turnへ予約するときは`cast_all.exs`を使える。
`cast_all.exs`は応答をbridge sideへ返さないため、返答が必要な依頼には使わない。
非同期通知への結果が必要なら、worktreeまたはbridge logへ残すよう明示する。
全playerに知らせる必要がない通知には使わない。

## 対話と統合

- leadが「あなた」「you」などの二人称で見解や反応を求めた場合は、partner自身への問いかけである可能性を重く見る。固定のrouting ruleにはせず、playerへ相談する場合でもpartner自身の見立てを先に返すことを検討する
- playerの返答をそのまま正解扱いせず、依頼範囲、実diff、検証結果との整合性を見る
- player間で結論が異なる場合は、leadに違いと判断材料を示すか、焦点を絞ってplayerへ戻す
- playerとのやりとりが続いても、leadへ現在の判断と次の選択を見える状態に保つ
- 方針、範囲、権限、外部作用を変える必要が出たら、player判断だけで広げずleadへ確認する

固定のworker→reviewer手順は設けない。
レビューが必要なら、その時点で適切なplayerを選ぶ。

## 文脈を切り替える

- 同じ話題を続ける: 同じplayerへ差分だけを送る
- 長い話題を引き継ぐ: 重要情報が成果物またはbridge logにあることを確認して`/compact`する
- 無関係な話題へ移る: `/clear`するか別playerを使う
- compact後にplayerとの関係を再把握する: `overview.exs`または`overview_all.exs`を使う

## bridge log

bridge logを使う場合は[bridge-log.md](bridge-log.md)を読む。
直接会話を置き換えず、複数player間の補助文脈と非同期連絡に使う。

pushまたはbridge作業の終了前に、bridge logのローカルrefを確認する。
必要な情報を通常の成果物へ残したうえで、同referenceの終了手順に従って掃除する。
