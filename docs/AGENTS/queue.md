## ACTIVE — TC-WIDGET-CN-V2A
ID: TC-WIDGET-CN-V2A
Title: Watch widget 文案中文化（v2a，仅改文案）
AssignedTo: Executor

Goal:
- 小组件/Complication 显示中文文案：
  - 状态：拍摄中 / 选片中 / 已停止（短文案：拍摄 / 选片 / 停止）
  - “Elapsed” -> “用时”
  - “Updated/Last updated” -> “更新 HH:mm”（24小时制，不出现“上午/下午”）

Scope (Allowed files ONLY):
- PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift
- docs/AGENTS/exec.md（只追加记录，允许提交）

Forbidden:
- 不允许修改 project.pbxproj / Info.plist / entitlements / 任何目标配置
- 不新增/删除 target，不改任何 build settings
- 不改共享存储结构（不新增 keys，不改写入逻辑）

Acceptance:
- accessoryRectangular：三行中文（状态 / 用时 xx:xx / 更新 HH:mm）
- accessoryCircular & accessoryCorner：短中文（拍摄/选片/停止），必要时仍显示用时
- xcodebuild 构建通过（CODE_SIGNING_ALLOWED=NO 可）：
  - watch app scheme + widget scheme

StopCondition:
- PR opened to main（不合并）
- CI green
- exec.md 追加“改了哪些文案 + 时间格式 + 验证命令”
- STOP
