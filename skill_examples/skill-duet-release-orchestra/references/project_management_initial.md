# Project Management Initial Setup

Use this reference when `docs/project_management/` is missing or incomplete.

The orchestrator must not create or edit these files directly while operating in release orchestra mode.
It should ask the user before initialization, then delegate creation to `scribe` or switch to an explicitly approved non-orchestra setup task.

## Directory Shape

```text
docs/project_management/
  README.md
  state.md
  roadmap.md
  releases.md
  release_<name>/
    kanban.md
    <ticket>.md
  quickfix/
    README.md
    done/
  incubator/
    README.md
```

Do not create `project_status.md`.

## README.md Template

````markdown
# Project Management

このディレクトリは、長めの作業の状態、判断、検証結果を残す場所です。
運用ルールの正本はこの README です。

## Purpose

- release を story ticket に分け、入力、出力、変換、制約、除外、検証を明確にする
- 重要な判断、検証結果、未解決事項を会話文脈だけに閉じ込めない
- 中断後に、次の AI または人が状態を読み直せるようにする
- 実装、レビュー、記録を混同しない

## Directory

```text
docs/project_management/
  README.md
  state.md
  roadmap.md
  releases.md
  release_<name>/
    kanban.md
    <ticket>.md
  quickfix/
    README.md
    ticket-*.md
    done/
      ticket-*.md
  incubator/
    <note>.md
```

`releases.md` の release 見出し名は台帳上の正名であり、`state.md` の `release_focus` はその名前に合わせます。

## Read Order

通常の再開時に必ず読む入口は `state.md` だけです。

`state.md` は軽い入口です。
今の release、割り込み、次に読むべき場所を短く置きます。
作業を進める場合は、`docs/project_management/<release_focus>/kanban.md` と Current ticket を読みます。
`state.md` がない、または `release_focus` が未設定の場合だけ、`releases.md` の上部 outline を読みます。

`roadmap.md` は予定や候補を確認するときだけ読みます。
`incubator/` は release に属さない仮説や概念メモを探す必要があるときだけ参照します。
`quickfix/` は release 未満の小修正をその場で扱うときだけ参照します。

## File Roles

`state.md`:
毎回読む軽い入口。
現在注目する release と、一時的な割り込みだけを書く。
詳細な状態、判断、検証、Current ticket は持たない。

`roadmap.md`:
今後の予定や候補を書く。
定義済み release の一覧、今の状態、完了済み release は置かない。

`releases.md`:
すでに release として定義したまとまりの台帳。
上部に全体 outline を置き、下に release 名ごとの見出しを置く。
Current / Completed のような状態見出しは持たない。
ticket 状態は各 release の kanban に置く。
release レベルの Summary、Result、Decisions、Not Needed、Carry Over もここに置く。
Purpose は release 開始時の意図、Summary は実施結果の現況を書く。
作業履歴、詳細な検証、迷いのログは ticket に残す。
release レベルのまとめは、release exit 時、または release の主要方針が変わったときに更新する。

`release_<name>/kanban.md`:
release 内の ticket 状態を管理する。
`Current`、`Todo`、`Done` の3区分を持ち、Current ticket は原則1つにする。

`release_<name>/<ticket>.md`:
ticket の詳細を書く。
重要な事実、判断、検証結果、未解決事項、引き継ぎはここに残す。

`quickfix/README.md`:
quickfix の軽い運用ルールを書く。
kanban、Current、Todo、release 台帳は持たない。

`quickfix/ticket-*.md`:
release にするほどではない未着手の小修正を書く。
直下は未着手 ticket だけにする。

`quickfix/done/ticket-*.md`:
完了した quickfix ticket を置く。
完了後は直下から `done/` へ移す。

`incubator/<note>.md`:
release 非依存の発想、仮説、概念メモを書く。
正式な作業対象にする場合は、該当 release と ticket へ必要部分を移す。

## Release And Ticket Size

`release` は、project を直列に分解したときの一つの区切り単位です。
小さい改修、単発調査、局所的な実装を分類するための箱ではありません。
明確な区切りがない限り、新しい release は作らず、現在の release を保ちます。

release を切るのは、現在のまとまりを Summary / Result / Decisions / Carry Over として閉じ、
次のまとまりを別の目的、前提、または到達点で始める必要があるときに限ります。
コード公開に限らず、調査、設計、実装、検証、文書化のまとまりも release になり得ますが、
終了時に「この区切りで何が進み、何を次へ送るか」を説明できる大きさにします。

`ticket` は release の中の story です。
作業名ではなく、利用者から見て「これをした」と言える出力物を持つ単位にします。

`quickfix` は release 未満の小修正です。
直下の ticket は未着手として扱い、完了したら `quickfix/done/` へ移します。
kanban、Current、Todo、`releases.md` の更新は使いません。
大きい、判断が多い、複数画面に広がる、または設計が必要なものは quickfix に置かず、incubator、roadmap、または release へ送ります。

## State Rules

- `state.md` の `release_focus` は原則1つにする
- `state.md` は常時読む入口なので、今の割り込みと再開に必要な短い note だけを書く
- active release board の Current ticket は原則1つにする
- 会話履歴、AIの内部文脈、duet entry の文脈は状態の原本にしない
- `state.md` は軽いブックマークであり、詳細な判断や検証の原本にしない
- `incubator/` の note は状態の原本にしない
- 重要な事実、判断、検証結果、未解決事項、引き継ぎは ticket に残す
- Done へ移す前に Done Criteria と Verification を確認する

## Board Rules

- `Todo` の並びは、上から順に着手優先度を表す
- `Current` が `None` の場合、原則として `Todo` の先頭を `Current` に移してから着手する
- `Ticket Candidates` を置く場合、その並びも上から順に ticket 化の候補順を表す
- `Ticket Candidates` は任意であり、候補整理が必要な release だけに置く
- `Order` と `Selection Rules` は任意であり、ticket 順序の決め方を明示する必要がある場合だけ置く
- `Current`、`Todo`、`Ticket Candidates` がすべて `None` または空の場合は、無理に `Current` を作らず、release exit か追加 ticket の必要性を確認する

## Ticket Format

ticket 詳細は最低限この見出しを使います。

```markdown
# <ticket-name>

## Goal

## Scope

## Done Criteria

## Notes

## Decisions

## Verification

## Handoff
```

## Ticket Before Start

ticket を作る前に、次を短く書ける状態にします。

- 入力: 何を材料にするか
- 出力: 何を作る、またはどういう状態にするか
- 変換: 入力から出力へ何をどう変えるか
- 制約: 何を保つか
- 除外: 何を変えないか
- 検証: 何で正しさを確認するか

これらが書けない場合は、実装 ticket ではなく調査 ticket、設計 ticket、または前提整理にします。
````

## state.md Template

```markdown
# State

release_focus: release_<name>

interruptions:
- None

notes:
- 常時読む入口はこのファイルだけ。作業を進める場合は `release_focus` の kanban と Current ticket を読む。
```

## roadmap.md Template

```markdown
# Roadmap

このファイルは、今後の予定や候補を置く計画文書である。
定義済み release とその結果は `releases.md` に置く。

## Planned Releases

- `release_<next>`: <予定または候補の release>

## Notes

- <今後の release 候補を読むための長期前提>
```

## releases.md Template

```markdown
# Releases

このファイルは、すでに release として定義したまとまりの台帳である。
予定や候補は `roadmap.md` に置く。
ticket 状態は各 release の kanban に置く。
release レベルの Summary、Result、Decisions、Not Needed、Carry Over もここに置く。

## Outline

- 今の作業入口は `state.md` の `release_focus` を正とする。
- release 内 ticket の Current / Todo / Done は、このファイルではなく各 kanban を正とする。

## release_<name>

- Status: active
- Board: [kanban](./release_<name>/kanban.md)
- Release is: <この release は何か>

### Purpose

### Summary

### Result

None

### Decisions

- None

### Not Needed

- None

### Carry Over

- None
```

## release_<name>/kanban.md Template

```markdown
# Release: <release name>

## Release Goal

<この release で利用者が何をできるようになるか>

## Exit Criteria

- <release を閉じられる条件>

## Current

- None

## Todo

- [ticket-001](./ticket-001.md): <short goal>

## Done

- None

## Ticket Candidates

- None
```

## Ticket Template

```markdown
# ticket-001

## Goal

<user value or target state>

## Scope

In:
- <allowed files or behavior>

Out:
- <explicitly excluded work>

## Done Criteria

- <observable completion condition>
- <required verification>

## Notes

- 入力:
- 出力:
- 変換:
- 制約:
- 除外:
- 検証:

## Decisions

- <decision and reason>

## Verification

- Not run yet.

## Handoff

- <short context needed after compact or interruption>
```

## quickfix/README.md Template

````markdown
# Quickfix

release 未満の小さい修正 ticket を置く場所です。

## Directory

```text
docs/project_management/quickfix/
  README.md
  ticket-*.md
  done/
    ticket-*.md
```

## Rules

- `quickfix/` 直下は未着手 quickfix ticket だけにする
- 完了した ticket は `quickfix/done/` へ移動する
- kanban、Current、Todo は作らない
- `releases.md` は触らない
- 大きい、判断が多い、複数画面に広がる、または設計が必要なものは quickfix に置かず、incubator / roadmap / release へ送る
- quickfix ticket は、その場で実行できる小修正だけにする
````

## incubator/README.md Template

```markdown
# Incubator

このディレクトリは、release に属さない発想、仮説、概念メモを一時的に置く場所です。

ここにある note は実行中 ticket ではありません。
`roadmap.md`、release kanban、Current ticket、Done 判定の原本にしません。

## Use Cases

- release にまだ接続しない考え方のヒント
- Done Criteria をまだ持たない仮説
- 後で設計文書、ticket、roadmap に昇格するかもしれない論点
- すぐ実装や調査へ進めると歪むが、失いたくない観点

## Rules

- note ごとに `Status` を書く
- 正式な作業対象にする場合は、該当 release の kanban と ticket へ必要部分を移す
- `promoted` にする場合は昇格先を、`deferred` / `discarded` にする場合は理由を note に残す
- 状態の原本として扱わない

## Status

- `raw`: 会話や違和感から残した未整理メモ
- `hypothesis`: 作業可能な仮説になりつつあるメモ
- `to-triage`: どこかの release / ticket へ移すか判断待ち
- `promoted`: 正式な ticket、設計文書、roadmap へ移した
- `deferred`: 残すが当面扱わない
- `discarded`: 採用しない理由を残して閉じた
```

## Initialization Prompt For Scribe

Use a short prompt like this.

```text
docs/project_management/ が未作成です。
release orchestra 運用の初期状態として README.md、state.md、roadmap.md、releases.md、最初の release kanban、必要なら最初の ticket、quickfix/README.md、quickfix/done/、incubator/README.md を作成してください。
この reference の構造に従い、docs/project_management/ 以外は触らないでください。
不明な release 名や ticket 名は、作成前に質問してください。
```
