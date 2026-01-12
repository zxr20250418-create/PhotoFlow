## ACTIVE — TC-WIDGET-CN-V2B
ID: TC-WIDGET-CN-V2B
Title: 小组件三态中文显示（拍摄/选片/停止）V2B
AssignedTo: Executor

Goal:
- widget/complication 显示三态中文：
  - 拍摄中 / 选片中 / 已停止（短文案：拍摄 / 选片 / 停止）
- 保持“用时”“更新 HH:mm”不变（24小时制，不出现上午/下午）

Scope (Allowed files ONLY):
- PhotoFlow/Shared/WidgetStateStore.swift
- PhotoFlow/PhotoFlowWatch Watch App/ContentView.swift（仅在写 widget state 的位置改）
- PhotoFlow/PhotoFlowWatchWidget/PhotoFlowWatchWidget.swift
- docs/AGENTS/exec.md（追加记录）

DataContract:
- 新增 shared store key：`pf_widget_stage` (String)
- 值域：`shooting` / `selecting` / `stopped`
- 若缺失则默认 `stopped`；不得崩溃

Forbidden:
- 禁止修改 project.pbxproj / Info.plist / entitlements / targets / build settings
- 禁止重构、禁止改业务逻辑（只改“写入 stage + 读取映射显示”）

Acceptance:
- accessoryRectangular：三行中文（状态 / 用时 xx:xx / 更新 HH:mm）
- accessoryCircular + accessoryCorner：短中文（拍摄/选片/停止）
- xcodebuild 通过（CODE_SIGNING_ALLOWED=NO 可）：
  - PhotoFlowWatch Watch App
  - PhotoFlowWatchWidgetExtension
  - （可选但建议）PhotoFlow -sdk iphoneos（避免再触发装完消失）
- PR opened to main（不合并），CI green，exec.md 写明 keys+验证命令；STOP
