# Task Queue
#
# NOTE: This file is the only coordination channel. Keep exactly one active task card.

## TC-RG-HARDGATE — Enforce RG-V1 as ship_2stage hard gate

AssignedTo: Exec
Goal: 把 `RG-V1` 变成 `scripts/ship_2stage.sh` 的硬门禁（默认必须通过 AUTO+手工两道验收），并提供显式逃生开关 `BYPASS_RG=true`。
Scope: 仅允许修改 `scripts/auto_gate.sh`、`scripts/ship_2stage.sh`、`scripts/evidence_pack.sh`（可新增 `docs/AGENTS/verify_auto.md` 作为产物文件）；可运行 `scripts/ship_2stage.sh` 做一次 `pipeline-smoke` 验证；允许走完整一键合并并落 evidence 流程。
Forbidden: 禁止改任何业务代码（`*.swift`、`*.pbxproj`）；禁止改 `docs/SPEC.md`、`docs/DECISIONS.md`、`docs/PLAN_*.md`；禁止引入持久化/数据库迁移。
Acceptance: (1) `scripts/auto_gate.sh` 默认输出从 `docs/AGENTS/verify.md` 改为 `docs/AGENTS/verify_auto.md`，且支持用 env 覆盖输出路径；(2) `scripts/ship_2stage.sh` 先运行 `auto_gate.sh` 并检查 `verify_auto.md` 含 `AUTO_GATE=PASS` 否则退出；再检查 `docs/AGENTS/verify.md` 含一行 `RG-V1: PASS` 否则退出并提示先手工验收填 PASS；提供 `BYPASS_RG=true`（默认 false）才可跳过 RG 检查；(3) `scripts/evidence_pack.sh` 将 `docs/AGENTS/verify_auto.md` 与 `docs/AGENTS/verify.md` 各自前 200 行写入 evidence；(4) 使用 `scripts/ship_2stage.sh` 跑一次 `pipeline-smoke`（docs-only 改动即可）验证通过；(5) 使用 `scripts/ship_2stage.sh` 完成一键合并并落 evidence。
StopCondition: 提交 1 次 commit（message 必须为 `chore: enforce RG-V1 as ship gate`）；最终在 `docs/AGENTS/exec.md` 汇报并输出：PR 链接 + evidence 路径 + `main` HEAD，然后停止。
