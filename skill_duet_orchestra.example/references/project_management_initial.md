# Project Management Initial Setup

Use this reference when `docs/project_management/` is missing or incomplete.

The orchestrator must not create or edit these files directly while operating in orchestra mode. It should ask the user before initialization, then delegate creation to `scribe` or switch to an explicitly approved non-orchestra setup task.

## Directory Shape

```text
docs/project_management/
  README.md
  roadmap.md
  kanban_<phase>.md
  kanban_<phase>/
    <ticket>.md
```

Do not create `project_status.md`.

## README.md Template

```markdown
# Project Management

This directory is the source of truth for the orchestrator workflow.

## Read Order

1. `roadmap.md`
2. current phase kanban
3. current ticket, if one exists

## Rules

- Phases are not parallel. `roadmap.md` has exactly one current phase.
- Tickets are not parallel. The active kanban has at most one `Current` ticket.
- Important facts, decisions, verification results, and handoff notes must be written to ticket files.
- AI conversation history and duet entry context are not source of truth.
- The orchestrator does not edit files directly.
- `worker` performs ticket work.
- `reviewer` reviews diff and completion.
- `scribe` updates only `docs/project_management/`.

## Ticket State

- `Todo`: ready or planned, not started
- `Current`: the single active ticket
- `Done`: completed, verified, and recorded
```

## roadmap.md Template

```markdown
# Roadmap

## Current Phase

- `kanban_phase_001.md`: <phase name>

## Planned Phases

- `kanban_phase_002.md`: <phase name>

## Completed Phases

- None

## Notes

- <important project-level constraint or decision>
```

## kanban_<phase>.md Template

```markdown
# Kanban: <phase name>

## Current

- None

## Todo

- [ticket-001](./kanban_<phase>/ticket-001.md): <short goal>

## Done

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

- <investigation or work notes>

## Decisions

- <decision and reason>

## Verification

- Not run yet.

## Handoff

- <short context needed after compact or interruption>
```

## Initialization Prompt For Scribe

Use a short prompt like this.

```text
docs/project_management/ が未作成です。
オーケストレータ運用の初期状態として README.md、roadmap.md、最初の kanban、必要なら最初の ticket を作成してください。
この reference の構造に従い、docs/project_management/ 以外は触らないでください。
不明な phase 名や ticket 名は、作成前に質問してください。
```
