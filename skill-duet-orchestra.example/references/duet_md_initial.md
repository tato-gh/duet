# DUET.md Initial Setup

Use this reference when `DUET.md` is missing or does not define the entries required by the orchestrator skill.

The orchestrator must not edit `DUET.md` directly while operating in orchestra mode. It should ask the user before initialization, then delegate the file update to `scribe` or switch to an explicitly approved non-orchestra setup task.

## Required Entries

The orchestrator expects these entries.

- `worker`: writes source, tests, docs, and runs verification for one ticket
- `reviewer`: read-only review of diff, done criteria, risk, and verification gaps
- `scribe`: writes only `docs/project_management/`

Do not add `planner` by default. The orchestrator owns phase and ticket planning.

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
      docs/project_management/ の roadmap、active kanban、指定された ticket を原本として読み、
      依頼された ticket の Scope と Done Criteria の範囲だけで、調査、実装、テスト、必要なファイル更新を行います。
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
      作業担当、レビュー担当、依頼者の報告をもとに、roadmap、active kanban、ticket の Notes、Decisions、Verification、Handoff を更新してください。
      状態を二重管理せず、Done Criteria と Verification が満たされた場合だけ ticket を Done に移してください。
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
- ticket は直列で進め、active kanban の `Current` は1件だけにする
- `/compact` と `/clear` はオーケストレータが entry に送る
- ticket 完了後、オーケストレータは worker/reviewer に `/clear` を送る
- 長い ticket では Handoff 更新後、オーケストレータは worker に `/compact` を送る
- entry 設定変更後は Duet を再起動する
```

## Notes

- Keep `reviewer` read-only.
- Do not include `writableRoots` by default in shared examples; local absolute paths can leak environment details.
- Add `writableRoots` only in a private local `DUET.md` when sandbox-level write restriction is explicitly needed.
- Enable `networkAccess` only when the ticket explicitly requires external access.
