# DUET.md Initial Setup

Use this reference when `DUET.md` is missing or does not define the entries required by the release orchestrator skill.

The orchestrator must not edit `DUET.md` directly while operating in release orchestra mode.
It should ask the user before initialization, then switch to an explicitly approved non-orchestra setup task for the file update.

## Required Entries

The orchestrator expects these entries.

- `worker`: writes source, tests, docs, and runs verification for one ticket
- `reviewer`: read-only review of diff, done criteria, risk, and verification gaps
- `scribe`: writes only `docs/project_management/`

Do not add `planner` by default.
The orchestrator owns release and ticket planning.

## Example

This example intentionally omits `writableRoots`.
Project-local writes are allowed for `workspaceWrite` entries, and the role boundaries describe the intended write scope.
Do not put local absolute paths into shared `DUET.md` examples.

```markdown
---
node_name: "duet"
entries:
  - name: "worker"
    command: "codex app-server"
    role: >
      あなたは ticket 単位の作業担当です。
      docs/project_management/ の state、active release kanban、指定された ticket を原本として読み、
      必要に応じて releases、roadmap、プロジェクトの作業指示も確認します。
      依頼された ticket の Scope と Done Criteria の範囲だけで、調査、実装、テスト、必要なファイル更新を行います。
      ticket 着手前に、入力、出力、変換、制約、除外、検証が不明瞭な場合は、作業を進めず不足を報告してください。
      完了後は、変更ファイル、実行した検証と結果、未解決事項、次に必要な判断だけを短く返してください。
      重要な決定、検証結果、未解決事項、引き継ぎ情報は ticket 更新対象として明示してください。
      ticket 範囲外の変更、不要なリファクタ、破壊的操作、秘密情報の露出は避けてください。
      長く続く作業では、Handoff に残すべき内容を短く報告してください。
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: false

  - name: "reviewer"
    command: "codex app-server"
    role: >
      あなたは ticket と差分のレビュー担当です。
      指定された ticket、Done Criteria、最新 diff、worker の報告を読み、重大な問題、完了判定、追加検証だけを短く返してください。
      実装やファイル編集は行わず、リスク、仕様漏れ、テスト不足、範囲外変更を優先して指摘してください。
      入力、出力、変換、制約、除外、検証のいずれかが成果物とずれている場合は明示してください。
      問題がない場合も、残るリスクや未確認事項があれば明示してください。
    approval_policy: "never"
    thread_sandbox: "read-only"
    turn_sandbox_policy:
      type: "readOnly"
      networkAccess: false

  - name: "scribe"
    command: "codex app-server"
    role: >
      あなたはプロジェクト管理ファイル専用の記録係です。
      docs/project_management/ だけを更新してください。ソース、テスト、通常ドキュメント、設定ファイルは編集しません。
      作業担当、レビュー担当、依頼者の報告をもとに、state、releases、roadmap、active release kanban、ticket の Notes、Decisions、Verification、Handoff を更新してください。
      同じ状態を複数ファイルに重複して持たせません。
      state.md には現在注目する release、割り込み、再開に必要な短い note だけを書き、詳細な判断、検証、Current ticket は持たせません。
      roadmap.md には今後の予定や候補だけを書き、現在状態や完了済み release は持たせません。
      release レベルの Summary、Result、Decisions、Not Needed、Carry Over は releases.md に書きます。
      ticket 状態は active release kanban に書きます。
      Done Criteria と Verification が満たされた場合だけ ticket を Done に移してください。
      満たしていない場合は Done に移さず、不足を短く報告して差し戻してください。
      不明点や矛盾があれば編集前に報告してください。
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: false
---

# DUET

## Entries

- `worker`: ticket 単位の調査、実装、検証、必要なファイル更新
- `reviewer`: ticket と diff の read-only review
- `scribe`: `docs/project_management/` 専用の状態更新

## Operation Notes

- オーケストレータはファイルを直接編集しない
- `state.md` は軽い入口にし、詳細な判断や検証は ticket、kanban、releases に残す
- `roadmap.md` は今後の予定や候補だけに使う
- ticket は原則直列で進め、active release kanban の `Current` は1件だけにする
- `/compact` と `/clear` はオーケストレータが entry に送る
- 長い ticket では Handoff 更新後、オーケストレータは worker に `/compact` を送る
- entry 設定変更後は Duet を再起動する
```

## Notes

- Keep `reviewer` read-only.
- Do not include `writableRoots` by default in shared examples; local absolute paths can leak environment details.
- Add `writableRoots` only in a private local `DUET.md` when sandbox-level write restriction is explicitly needed.
- Enable `networkAccess` only when the ticket explicitly requires external access.
