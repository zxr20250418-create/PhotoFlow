# HANDOFF_CHATGPT.md — ChatGPT 交接包模板（复制到新对话用）

> 用法：当你觉得上下文要满了，在旧对话对 ChatGPT 说：
> “按 HANDOFF_CHATGPT 模板生成当前交接包（精简版）”
> 然后把生成内容整体复制到新对话即可。

---

## 0) 一句话目标（North Star）
- 我现在要完成什么（1 句）：

## 1) 项目基本信息（Repo Facts）
- Repo 名称：
- GitHub：
- 本地路径：
- 默认分支：
- 语言/平台：
- 关键工程路径（例如 *.xcodeproj / project.yml）：
- CI 工作流文件：
- 关键脚本入口（build/test/lint/versions gate）：

## 2) 当前状态快照（State Snapshot）
- 当前 HEAD（git rev-parse HEAD）：
- 当前分支（git branch --show-current）：
- 工作区是否干净（git status -sb）：
- 远端同步（git rev-parse origin/main）：
- 最近 5 条提交（git log --oneline -n 5）：

## 3) 已完成（Done）
- [ ] A. 仓库初始化（docs/ scripts/ .github/）
- [ ] B. 最小可构建工程（iOS + watchOS v0）
- [ ] C. CI 可跑通（Actions 有记录）
- [ ] D. main 分支保护/门禁（要求 PR + required checks）
- [ ] 其它（按实际补充）：

## 4) 未完成 / 阻塞点（Open Issues / Blockers）
- 问题 1：
  - 现象：
  - 期望：
  - 已尝试：
  - 当前证据（日志/截图/链接）：
- 问题 2：

## 5) 风险点与踩坑记录（Risks / Pitfalls）
- 近期踩坑：
- 根因（我认为）：
- 规避策略（以后怎么避免）：

## 6) 下一步行动清单（Next Actions）
> 要求：每条都能在 10–30 分钟内推进，并且可验证。
1. 
2. 
3. 

## 7) “证据包清单”（给 ChatGPT/Codex 的最小输入）
> 你不懂代码时，靠证据包也能让 AI 精准判断进度与问题。
- 终端输出（按顺序粘贴）：
  1) pwd
  2) git status -sb
  3) git log --oneline -n 10
  4) ls（关键目录）
  5) 失败日志（最后 80–120 行）
- GitHub 截图/链接：
  - Actions run 链接：
  - PR 链接：
  - Branch protection / required checks 截图：

## 8) 常用命令（可复现）
- 本地构建（iOS）：
- 本地构建（watchOS）：
- 版本一致性 gate：
- 触发 CI（空提交/脚本）：
- 回退（revert/reset）：

## 9) 约束/偏好（Working Agreement）
- 产出限制：每次最多多少行输出、不要贴整文件/整 diff：
- 变更策略：小步提交、PR 合并、main 永远可构建：
- 禁止事项：例如不引入 XcodeGen/Tuist、P0 不加 complication：

## 10) 索引行（Index）
date=YYYY-MM-DD | repo=... | branch=... | head=... | status=... | next=...
