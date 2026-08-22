# DUET.md initial roster

Use this reference only when bridge side needs to initialize or materially revise a bridge roster.

`DUET.md`は固定workflowではなく、起動可能なplayerのrosterとして設計する。
roleには案件固有の担当を固定せず、entry名、長期的な能力、通常の姿勢、権限境界を書く。
model、reasoning、service tier、sandboxは想定用途に合わせて明示する。

初期rosterは現在の依頼だけを処理する最小編成ではなく、project決定前から利用可能な能力のportfolioとして提案する。
応答速度、思考の深さ、read/write権限、同時に依頼できる実行容量に幅を持たせる。
並列に成果物を作る可能性があるなら、案件固有の担当を固定せず、複数のworkspace-write playerを用意してよい。

起動しても使わないplayerや、長時間待機するplayerがいてよい。
全playerを使う前提でrosterを作らないが、使わない可能性を理由に能力や実行容量を現在の依頼だけへ切り詰めない。

`DUET.md`には恒常的な能力、model、reasoning、権限を書く。
現在の担当、ファイル範囲、作業順序、同時編集の調整は、具体的な依頼が決まった時点でbridge sideが扱う。
潜在的な編集競合を理由に初期rosterのworkspace-write playerを一人へ限定しない。

## skillを配置する

bridge sideとCodex app-serverのplayerが同じskillを参照できるよう、プロジェクトの`.codex/skills/`へ配置する。

```bash
mkdir -p .codex/skills
ln -s /path/to/duet/skill_examples/skill-duet .codex/skills/skill-duet
ln -s /path/to/duet/skill_examples/skill-duet-bridge .codex/skills/skill-duet-bridge
```

## roster例

以下は出発点であり、固定の必須entryではない。

```markdown
---
node_name: "duet"
entries:
  - name: "fast_generalist"
    command: "codex app-server"
    role: >
      duet bridge体系のplayer fast_generalist。
      案件固有の職務は固定せず、短い調査、整理、比較、初期案を素早く返す。
      bridge sideから依頼された範囲だけを扱い、作業がなければ待機する。
    model: "gpt-5.6-luna"
    reasoning_effort: "high"
    service_tier: "fast"
    approval_policy: "never"
    thread_sandbox: "read-only"
    turn_sandbox_policy:
      type: "readOnly"
      networkAccess: false

  - name: "deep_generalist"
    command: "codex app-server"
    role: >
      duet bridge体系のplayer deep_generalist。
      案件固有の職務は固定せず、難しい設計、反証、複数案の評価を深く考える。
      bridge sideから依頼された範囲だけを扱い、作業がなければ待機する。
    model: "gpt-5.6-sol"
    reasoning_effort: "xhigh"
    approval_policy: "never"
    thread_sandbox: "read-only"
    turn_sandbox_policy:
      type: "readOnly"
      networkAccess: false

  - name: "work_generalist"
    command: "codex app-server"
    role: >
      duet bridge体系のplayer work_generalist。
      案件固有の職務は固定せず、調査、設計、実装、テストを依頼範囲内で行う。
      bridge sideから依頼された範囲だけを扱い、作業がなければ待機する。
    model: "gpt-5.6-terra"
    reasoning_effort: "high"
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: false

  - name: "deep_work_generalist"
    command: "codex app-server"
    role: >
      duet bridge体系のplayer deep_work_generalist。
      案件固有の職務は固定せず、複雑な調査、設計、実装、テストを依頼範囲内で行う。
      bridge sideから依頼された範囲だけを扱い、作業がなければ待機する。
    model: "gpt-5.6-sol"
    reasoning_effort: "xhigh"
    approval_policy: "never"
    thread_sandbox: "workspace-write"
    turn_sandbox_policy:
      type: "workspaceWrite"
      networkAccess: false
---

# DUET

このDUET.mdはduet bridgeで利用可能なplayer rosterを定義する。
現在の任務やproject編成は固定せず、bridge sideがleadとの対話を通じて動的に決める。
```

既存`DUET.md`がある場合は、名称、role、model、権限を勝手に置き換えない。
entryの追加・削除、権限変更、model変更はleadと確認する。

`DUET.md`は起動時に読み込まれる。
rosterを変更した場合はDuetを再起動して反映する。
