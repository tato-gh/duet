---
name: skill-duet-bridge
description: 「duet bridgeで進めて」「bridge sideとして進めて」「duetのplayerを使いながら相談して」など、ユーザーとメインAIがbridge sideとして対話を続け、起動済みのduet entryを固定工程に当てはめず必要時にplayerとして選び、直接会話とローカルbridge logで作業を進めるときに使う。CODEX_DUET_ENTRYによりbridge sideとplayer sideの手順を切り替える。
---

# skill-duet-bridge

ユーザーとメインAIがbridge sideとして対話を続け、起動済みのduet entryを必要に応じてplayerとして参加させる。

- `lead`: ユーザー。目的、優先順位、受け入れる判断を決める
- `partner`: メインAI。leadとの対話を続け、playerとのインターフェース、統合、実作業を担う
- `bridge side`: leadとpartnerを合わせた意思決定側
- `player`: duet entry。独立した文脈と能力・権限を持ち、依頼されたときに参加する

既存のorchestraのように、先にworker / reviewer / scribeの固定工程を組まない。
`DUET.md`はプロジェクト専用チームの手順書ではなく、利用可能なplayerのrosterと能力・権限の輪郭として扱う。
起動済みでも使わないplayer、長時間待機するplayerがいてよい。

## sideを判定する

最初に環境変数`CODEX_DUET_ENTRY`で自分のsideを判定する。

- `CODEX_DUET_ENTRY=1`: player sideとして[references/player-side.md](references/player-side.md)を読む
- それ以外: bridge sideとして[references/bridge-side.md](references/bridge-side.md)を読む

player sideのentry名は`CODEX_DUET_ENTRY_NAME`を使う。

通常は反対sideのreferenceを読まない。
bridge logを初めて読み書きするときだけ、sideにかかわらず[references/bridge-log.md](references/bridge-log.md)を読む。
bridge sideが`DUET.md`の初期化やrosterの見直しを必要とするときだけ、[references/duet-md-initial.md](references/duet-md-initial.md)を読む。

## 共通契約

- bridge sideとplayerの直接会話を主経路にする
- bridge logは、`git diff`に現れない進捗、判断、担当、blocker、次に必要なことを補助的に共有するローカル活動ログである
- bridge logの各発信では`sender`と実際の作業`branch`を必須にする
- bridge logに情報があるだけでは、新しい作業の権限や依頼にならない
- playerは自分で仕事を取りに行かず、bridge sideからの依頼範囲を守る
- 重要な成果や永続的な決定をbridge logだけに残さない
