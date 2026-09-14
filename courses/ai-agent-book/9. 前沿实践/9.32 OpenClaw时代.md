# 第 32 章：OpenClaw 时代

> **本地 Agent Harness 的核心不是工具有多强大——而是循环有多可靠。你能让 Agent 在本地机器上跑 100 步不崩溃，比让它跑 10 步但第 11 步幻觉来比，有用得多。**

---

> **⏱️ 快速通道**（5 分钟掌握核心）
>
> 1. OpenClaw 时代 = 本地自主 Agent + 计算机控制 + 可编程钩子
> 2. Agent Harness = 事件驱动的 for 循环：LLM 调用 → 工具执行 → 上下文追加 → 循环检测
> 3. 计算机控制两条路：Accessibility Tree（语义精确）vs 坐标点击（通用但脆弱）
> 4. Hooks = 4 个事件点（PreToolUse/PostToolUse/SessionStart/Stop），exit 2 拒绝执行
> 5. 权限引擎 5 层：硬封锁 → 配置拒绝 → 复合命令拆解 → 配置允许 → 用户审批
> 6. 9 个循环探测器：从重复调用到搜索升级，防止 Agent 原地打转
>
> **10 分钟路径**：32.1 → 32.3 → 32.4 → 32.5 → Shan Lab

---

## 32.1 开场：当 Claude Code 出现的那天

2025 年 2 月，Anthropic 发布了 Claude Code。

我盯着那个终端界面看了很久。一个 AI 在我的 macOS 上自主读文件、改代码、跑测试——不是在云端沙箱，是在我的本地机器上。它读的是真实的项目，改的是真实的代码，跑的是真实的 CI。

几个月后，我看到 OpenClaw 的演示：AI 接管浏览器、点击界面、填写表单、截图确认。

这不是远程调用 API。这是 **AI 在本地运行，控制本地计算机**。

那一刻我意识到，这是一个新范式的开始——**OpenClaw 时代**。

OpenClaw 指的不是某个特定产品，而是一类架构：AI Agent 在用户的本地机器上运行一个持续循环，通过调用本地工具（文件系统、Shell、GUI 控制）完成任务，全程可审计、可中断、可扩展。

这一章讲我们怎么实现这个。

---

## 32.2 什么是 OpenClaw 时代？

### 三个代表

2025 年，这类工具密集涌现：

| 产品 | 厂商 | 核心能力 |
|------|------|----------|
| Claude Code | Anthropic | 终端 + 代码 Agent，本地文件操作 |
| Devin | Cognition | 云端 VM + 完整开发环境 |
| OpenClaw | 开源社区 | 本地浏览器 + 屏幕控制 Agent |
| shan | Kocoro | 本地 macOS Agent，Shannon 生态 CLI |

它们的共同点：**Agent 不只是回答问题，而是采取行动**。

### 本地优先的理由

相比云端沙箱，本地 Agent 有三个不可替代的优势：

**1. 访问本地状态**：已登录的账号、本地数据库、私有证书、公司 VPN 后的内部服务——这些云端 Agent 碰不到，本地 Agent 直接可用。

**2. GUI 原生控制**：macOS Accessibility API 暴露的应用状态（按钮文字、输入框内容、菜单层级），比网页 DOM 更精确，比截图更可靠。用坐标点击是最后手段；用语义 API 是正确做法。

**3. 用户实时可见**：Agent 在屏幕上操作，用户全程可观察、可中断。透明度是信任的前提。

### 代价

本地 Agent 也有代价：**安全边界复杂**。

云端沙箱的安全很简单——容器隔离，销毁即干净。本地 Agent 没有隔离边界，一条 `rm -rf ~` 命令就能造成不可逆损失。你需要主动构建权限控制。

这就是为什么好的 OpenClaw 实现，不是只有"能做什么"，还要精心设计"不能做什么"。

---

## 32.3 Agent Harness：循环的骨架

OpenClaw 时代的核心技术是 **Agent Harness**——驱动 Agent 持续运行的执行框架。

它本质上是一个 `for` 循环：

```
for i := 0; i < maxIter; i++
    ├── 调用 LLM，获得响应
    ├── 如果没有工具调用 → 返回最终文本
    └── 如果有工具调用 → 执行工具 → 追加结果 → 继续
```

但从这个骨架到生产可用，有大量细节。

![Agent Harness 架构](assets/agent-harness-loop.svg)

### 三阶段执行模型

每个包含工具调用的迭代，分三个阶段处理：

**阶段一：串行准入**（每个工具调用依次检查）
- 去重：同一响应内相同的工具调用只执行一次
- 跨迭代缓存：上一轮成功调用的结果直接复用，不重复执行
- 权限检查：5 层引擎（见 32.5）
- 用户审批：需要审批的工具暂停等待
- Pre-hook：hook 可以在这里阻止执行（见 32.4）

**阶段二：并行执行**（已通过准入的工具并发运行）

一个 LLM 响应可能包含多个工具调用。通过准入后，它们用 `sync.WaitGroup` 并发执行，互不阻塞。

**阶段三：串行收尾**（依次处理结果）
- 运行 Post-hook
- 写入审计日志
- 循环检测（9 个探测器，见 32.6）
- 追加工具结果到对话上下文

这个模型的关键设计：**准入串行保证安全，执行并行保证效率，收尾串行保证一致性**。

### 上下文压缩

长任务的上下文会不断增长，最终超出 LLM 的限制。

shan 在每次 LLM 调用前检查 Token 估算：

```
if 当前 Token > contextWindow * 0.85:
    调用 LLM 生成对话摘要
    用摘要替换中间历史
    保留：摘要 + 最近几轮 + 原始任务描述
```

85% 不是精确值，是经验值——留足 15% 给工具结果和下一轮响应，避免截断。

**关键细节**：摘要本身也是一次 LLM 调用，有失败风险。shan 追踪连续失败次数，超过 3 次后暂停压缩 5 个迭代，等待上下文自然消耗。

### 进度检查点

长任务容易漂移——Agent 做着做着忘记了最初目标。

shan 在达到 60% 迭代上限时，向上下文注入一条自检提示：

```
当前进度检查：你正在执行的任务是什么？
你已经完成了哪些步骤？
下一步应该做什么？
你是否还在朝着原始目标前进？
```

这不是 Human-in-the-Loop，是 **Agent 对自身的强制反思**。

### 反幻觉机制

模型有时会"假装调用工具"——在文本回复里写出工具调用的格式，而不是真的触发工具。

shan 检测这种模式，并向模型发送一条强制纠正消息：

```
你刚才把工具调用写在了文本里，而不是实际调用它们。
请重新生成，使用真正的工具调用。
```

这防止了模型用"假装做了"来绕过实际执行。

---

## 32.4 本地工具层：控制计算机的两条路

shan 支持两种本地计算机控制方式，各有适用场景。

### 路线一：Accessibility Tree（推荐）

macOS 的 Accessibility API（AXUIElement）暴露每个应用的完整 UI 语义树：按钮文字、输入框内容、复选框状态、菜单结构……每个 UI 元素都有语义标识，不依赖屏幕坐标。

读取 UI 树的大致流程：

```
1. 找到目标应用的 PID（通过 System Events AppleScript）
2. 获取应用的根 AXUIElement
3. 递归遍历 UI 树，提取元素属性
4. 返回 JSON 格式的树，带有引用 ID（如 "e14"）
5. 后续操作（click/press/set_value）通过引用 ID 定位元素
```

优势：**语义可靠，不受分辨率和缩放影响**。一个"提交"按钮，不管在哪个屏幕分辨率下，引用 ID 都指向同一个按钮。

劣势：**需要辅助功能权限**，并非所有应用都完整暴露 AX 树（Electron 应用支持参差不齐）。

代码参考：[`accessibility.go`](https://github.com/Kocoro-lab/shan)

### 路线二：坐标控制（兜底）

通过 macOS Quartz Event Services API 发送鼠标和键盘事件，直接操作屏幕坐标。

```
click(x=450, y=320)
type(text="Hello")
hotkey(keys=["command", "s"])
```

每次操作后自动截图（500ms 延迟），让 LLM 验证操作是否成功。

**Retina 屏幕处理**：macOS 的逻辑分辨率和物理分辨率不同。shan 自动检测缩放因子并转换坐标，避免点击偏移。

**输入文字**：短文本（≤20 字符）用 `osascript keystroke`；长文本通过剪贴板注入（保存原内容 → 写入新内容 → cmd+v 粘贴 → 恢复原内容），避免键盘模拟的字符丢失问题。

### 截图反馈循环

GUI 操作天然需要"看见"结果才能决定下一步。shan 的截图工具：
- 支持全屏、指定窗口（按 PID）、指定区域三种模式
- 压缩到最大 1200px 宽，以 base64 PNG 传给 LLM
- 自动清理旧截图：只保留最近 5 张，避免上下文爆炸

在 shan 内部，GUI 密集型任务（截图、computer、accessibility、browser）自动获得更高的迭代上限——因为操作 GUI 本身就需要更多步骤。

### 浏览器控制

shan 的浏览器工具有两个后端：

| 后端 | 原理 | 适用场景 |
|------|------|----------|
| Pinchtab | 外部浏览器服务 HTTP API | 优先使用，更稳定 |
| chromedp | 内嵌无头 Chrome | 无 Pinchtab 时兜底 |

关键设计：**独立浏览器配置文件**，完全隔离于用户自己的浏览器会话。Agent 浏览的内容不影响用户的 cookies 和历史记录。

浏览器工具的 `snapshot` 操作同样返回 AX 树（带引用 ID），后续 `click`/`type` 通过引用而非坐标操作，显著提升稳定性。

---

## 32.5 Hooks：可编程事件钩子

Hooks 是 OpenClaw 时代架构的标志性特性——让用户在 Agent 执行的关键时刻注入自定义逻辑。

第 6 章讲了 Shannon 服务端的 Hooks 设计。这里讲的是 **shan 本地 CLI 的 Hook 系统**，更轻量，更贴近用户。

### 4 个事件点

| 事件 | 触发时机 | 能阻止执行？ |
|------|----------|-------------|
| `PreToolUse` | 权限检查通过后，工具执行前 | **是**（exit 2） |
| `PostToolUse` | 工具执行完成后 | 否 |
| `SessionStart` | 会话开始时 | 否 |
| `Stop` | 会话结束时 | 否 |

### 配置

在 `.shannon/config.yaml` 中配置 hook：

```yaml
hooks:
  PreToolUse:
    - matcher: "bash"
      command: ".shannon/hooks/check-bash.sh"
  PostToolUse:
    - matcher: "file_edit|file_write"
      command: ".shannon/hooks/post-edit.sh"
  SessionStart:
    - command: ".shannon/hooks/on-start.sh"
  Stop:
    - command: ".shannon/hooks/on-stop.sh"
```

`matcher` 是正则表达式，匹配工具名称。空 matcher 匹配所有工具。

### Hook 协议

Hook 脚本通过 stdin 接收 JSON：

```json
{
  "event":         "PreToolUse",
  "tool_name":     "bash",
  "tool_input":    {"command": "rm -rf ./tmp"},
  "tool_response": null,
  "session_id":    "sess_abc123"
}
```

退出码约定：
- `0` = 允许
- `2` = **拒绝**（仅 PreToolUse 有效；stderr 内容作为拒绝原因返回给 LLM）
- 其他非零 = 警告，但不阻止

### 一个实际例子：防止删除生产配置

```bash
#!/bin/bash
# .shannon/hooks/check-bash.sh

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tool_input']['command'])")

if echo "$COMMAND" | grep -q "prod.*\.env\|\.env\.production"; then
    echo "拒绝：不允许操作生产环境配置文件" >&2
    exit 2
fi

exit 0
```

LLM 尝试执行 `cat .env.production` 时，这个 hook 会拦截，并把拒绝原因传回给 LLM：LLM 知道为什么被拒，可以调整策略。

### 安全约束

hook 命令有严格的路径限制：
- 必须使用 `./` 开头的相对路径，或 `~/.shannon/` 下的绝对路径
- 通过 PATH 解析的裸命令名（如 `python`）被拒绝——防止 PATH 劫持攻击

Hook 超时 10 秒，输出限制 10KB。超时时整个进程组被强制终止。

---

## 32.6 权限引擎：5 层防护

本地 Agent 的安全边界靠权限引擎维护。shan 的设计是 **5 层串行决策**：

```
工具调用请求
     │
     ▼
层 1：硬封锁常量
     │ rm -rf /、rm -rf ~、dd if=* of=/dev/*、curl * | sh...
     │ → 永久拒绝，不可覆盖
     ▼
层 2：配置拒绝列表
     │ permissions.denied_commands: ["git push --force", "*.prod.*"]
     │ → 拒绝
     ▼
层 3：复合命令拆解
     │ cmd1 && cmd2 || cmd3 | cmd4
     │ 每个子命令独立检查，任一被拒 → 整体拒绝
     │ 全部明确允许 → 整体允许
     ▼
层 4：配置允许列表
     │ permissions.allowed_commands: ["go test ./...", "npm run *"]
     │ → 自动允许
     ▼
层 5：用户审批
       → 暂停，等待用户 y/n
```

### 安全命令白名单

部分命令被标记为无需审批：`ls`、`pwd`、`git status`、`git diff`、`git log`、`go build`、`go test`、`make`、`cargo test`……

但有一条规则**不可绕过**：包含 Shell 操作符（`&&`、`|`、`>`、反引号、`$(...)`) 的命令永远不进白名单，必须经过用户审批或配置允许列表。

```
ls -la ./          → 自动允许（安全命令）
ls -la | grep .go  → 需要审批（包含管道）
go test ./...      → 自动允许
go test ./... && rm -rf ./tmp → 需要审批（复合命令）
```

### 跨工具类型的额外检查

不同工具类型有专项检查：
- **bash**：命令内容检查（上面的 5 层）
- **file_read/write/edit**：路径检查（符号链接解析，敏感文件模式匹配：`~/.ssh/*`、`*.pem`、`*credentials*`……）
- **http**：网络出口检查（localhost 始终允许；外部域名需要在允许列表或用户审批）

---

## 32.7 循环检测：9 个探测器

Agent 卡循环是 OpenClaw 架构里最难处理的问题之一。

模型在某些状态下会反复尝试同一件事——不是 bug，是模型对"再试一次可能成功"的过度乐观。你需要在循环失控之前识别并干预。

shan 维护一个长度为 20 的工具调用滑动窗口，用 9 个探测器并行分析。每个探测器返回三种结果：`Continue`（正常）、`Nudge`（发送警告给 LLM）、`ForceStop`（强制结束循环）。

| 探测器 | 触发条件 | 结果 |
|--------|----------|------|
| ConsecutiveDuplicate | 连续 2 次相同工具+参数 | Nudge → ForceStop |
| ExactDuplicate | 同一工具+参数在窗口内出现 3 次 | Nudge → ForceStop |
| SameToolError | 同一工具连续报错 4 次 | Nudge → ForceStop |
| FamilyNoProgress | 同类工具 3/5/7 次同主题调用 | Nudge → ForceStop |
| SearchEscalation | 连续 3 次搜索类工具调用 | Nudge（5 次 ForceStop） |
| NoProgress | 任何工具重复 8 次以上 | Nudge → ForceStop |
| ToolModeSwitch | 成功 GUI 操作后立刻切视觉工具 | Nudge |
| SuccessAfterError | 视觉工具出错后的修复操作 | Nudge |
| Sleep | bash 中调用 sleep（2/4 次）| Nudge → ForceStop |

### Nudge vs ForceStop

**Nudge**（轻推）：向对话上下文注入一条提示，告诉 LLM 它陷入了重复。LLM 有机会调整策略。

**ForceStop**（强制停止）：注入提示后，进行一次不带工具的最终 LLM 调用，让模型总结当前状态，然后退出循环。

如果 Nudge 连续触发 3 次以上，自动升级为 ForceStop。

### 为什么需要这么多探测器？

因为循环有很多模式。

最简单的是 ConsecutiveDuplicate：Agent 反复调用 `file_read("config.json")`。

更隐蔽的是 SearchEscalation：Agent 在 Google 上搜"Python 版本"，没找到，搜"Python3 版本"，没找到，搜"Python latest version"——明明应该换个思路，却一直在搜索家族里打转。

FamilyNoProgress 捕捉的是"同类型工具在同一主题上绕圈"的模式——即使每次参数略有不同。

Sleep 探测器看起来奇怪，但有真实价值：模型有时会写出 `sleep 5 && retry`，这通常意味着它在等待某个永远不会改变的外部状态，是陷入等待循环的前兆。

---

## 32.8 把它们串起来：一个完整的本地 Agent

现在把所有组件放在一起，看一个完整的本地 Agent 执行过程：

```
用户：帮我把项目里所有 TODO 注释整理成一个 issues.md

── 迭代 1 ──────────────────────────────────────
  LLM 调用
  └→ tool: bash, args: {command: "grep -rn 'TODO' ./src"}

  阶段 1（准入）:
    去重检查: 首次调用，通过
    权限检查: 层 4（grep 在安全命令列表中）→ 自动允许
    Pre-hook: 无匹配 hook，通过

  阶段 2（执行）:
    bash.Run() → 返回 47 行 TODO 列表

  阶段 3（收尾）:
    Post-hook: 无匹配
    审计日志: 写入 bash 调用记录
    循环检测: 正常，Continue
    追加结果到上下文

── 迭代 2 ──────────────────────────────────────
  LLM 调用
  └→ tool: file_write, args: {path: "issues.md", content: "..."}

  阶段 1（准入）:
    权限检查: 层 5（file_write 不在自动允许列表）→ 用户审批
    用户: y
    Pre-hook: 匹配 "file_edit|file_write" → 执行 post-edit.sh
    hook 退出码: 0 → 允许

  阶段 2（执行）:
    file_write.Run() → 写入文件成功

  阶段 3（收尾）:
    Post-hook: 执行 post-edit.sh（记录修改文件）
    审计日志: 写入 file_write 记录
    ReadTracker: 记录 issues.md 被写入（后续读取将解除缓存）

── 迭代 3 ──────────────────────────────────────
  LLM 响应无工具调用
  └→ "已将 47 个 TODO 整理到 issues.md，按模块分组。"

  检查: 无截断，无幻觉，非检查点后续
  返回最终文本
```

整个过程：3 个迭代，1 次用户审批，全程审计日志。

---

## 32.9 本地优先，云端协作

shan 有一个设计选择值得单独说：**本地工具执行 + 远程 LLM 推理**。

LLM 调用走 Shannon Gateway（云端）。工具执行留在本地。

这和 Claude Code 的模型一致（模型调用走 Anthropic API，工具运行在本地）。

这个分离有三个好处：

1. **计算分离**：LLM 推理在专用硬件上跑最有效率，本地执行在用户硬件上跑有完整权限
2. **数据边界**：文件内容、命令输出这些敏感数据，控制在你决定发送给 LLM 的部分
3. **离线降级**：理论上可以换成本地 LLM（Ollama 等），工具层不需要改变

但这也意味着：**shan 是一个薄客户端**。核心的编排逻辑（Agent Harness）在客户端，但 LLM 的推理能力依赖网络。

针对网络不稳定的场景，shan 实现了指数退避重试，并在重试失败后以当前最优结果优雅退出，而不是崩溃。

---

## 32.10 OpenClaw 时代的三条设计原则

回顾这一章的内容，可以抽象出构建本地 Agent Harness 的三条核心原则：

**原则一：安全是架构约束，不是功能**

权限引擎不是事后加上去的安全功能，它是整个工具调用链的必经路径。就像编译器的类型检查——你不能绕过它，也不应该绕过它。硬封锁命令列表不可配置，这是故意的。

**原则二：循环检测是 Agent 可靠性的核心**

评估一个 Agent Harness 的质量，最好的指标不是"能做多复杂的任务"，而是"任务失败时是否优雅退出"。9 个探测器守护的就是这个底线——让 Agent 知道何时停止尝试。

**原则三：Hooks 是给人的控制面，不是给 AI 的**

Hooks 的存在不是为了让 Agent 更强大，而是为了让**用户**能把自己的业务逻辑注入 Agent 流程，而不需要修改 Agent 本身的代码。这是"用户主权"的体现——你的 Agent，你说了算。

---

## Shan Lab（10 分钟上手）

本章对应 Shannon 生态的 CLI 工具 `shan`。代码和文档在 [https://github.com/Kocoro-lab/shan](https://github.com/Kocoro-lab/shan)。

### 必读（2 个文件）

- [`internal/agent/loop.go`](https://github.com/Kocoro-lab/shan) — Agent Harness 的核心实现。重点看：三阶段执行模型、上下文压缩触发条件（85% 阈值）、进度检查点逻辑、反幻觉检测

- [`internal/hooks/hooks.go`](https://github.com/Kocoro-lab/shan) — 4 个事件点的实现。重点看：Hook 协议（stdin JSON + exit code）、exit 2 拒绝机制、递归防护（inHook 互斥锁）

### 选读深挖（2 个）

- [`internal/agent/loopdetect.go`](https://github.com/Kocoro-lab/shan) — 9 个循环探测器的完整实现，理解 Nudge 和 ForceStop 的触发条件与升级逻辑

- [`internal/permissions/permissions.go`](https://github.com/Kocoro-lab/shan) — 5 层权限引擎，重点看硬封锁列表（不可配置的设计决策）和复合命令拆解逻辑

---

## 延伸阅读

- [Claude Code 设计文档](https://www.anthropic.com/engineering/claude-code-deep-dive) — Anthropic 官方对 Claude Code 架构的深度解读
- [OpenClaw 项目](https://github.com/opencolaw/opencolaw) — 社区开源的 OpenClaw 复现
- [macOS Accessibility API 指南](https://developer.apple.com/documentation/appkit/nsaccessibility) — AXUIElement API 官方文档
- [Anthropic Computer Use 文档](https://docs.anthropic.com/en/docs/build-with-claude/computer-use) — Claude 原生计算机控制能力

---

## 练习

### 练习 1：设计你的第一个 Hook

你在做一个帮助处理客户数据的 Agent。设计一套 Hook 配置：
- 防止 Agent 读取包含 "private" 或 "secret" 的文件
- 每次 bash 命令执行后记录到本地日志文件
- 会话结束时发送桌面通知

写出配置 YAML 和对应的 hook 脚本逻辑。

### 练习 2：循环探测器扩展

9 个探测器里没有一个专门处理"网络超时重试"——Agent 在 http 工具超时后反复重试同一 URL。

设计第 10 个探测器 `NetworkRetryStorm`：
- 触发条件是什么？
- Nudge 消息怎么写？
- 什么情况下升级到 ForceStop？

### 练习 3（进阶）：Accessibility Tree 遍历

macOS 的 AXUIElement 树可能非常深，直接递归遍历容易超出 LLM 上下文限制。

读 `accessibility.go` 的截断逻辑，回答：
1. 它如何决定截断哪些元素？
2. 截断后的输出还能支持引用 ID 操作吗？
3. 如果你需要找深层元素，该怎么做？

---

## 划重点

OpenClaw 时代的核心是：**把可靠的执行基础设施，交给一个自主运行的 Agent**。

要点：

1. **Agent Harness = 三阶段循环**：串行准入 → 并行执行 → 串行收尾
2. **计算机控制优先 AX Tree**：语义可靠，不怕分辨率变化
3. **Hooks 是用户控制面**：exit 2 是最强大的一行代码
4. **5 层权限引擎**：安全是架构约束，硬封锁不可绕过
5. **9 个循环探测器**：可靠性的核心，优雅失败比无限重试有价值
6. **85% 阈值触发压缩**：长任务的生命线

**OpenClaw 时代不会停止**。随着本地 AI 模型变强，本地 Agent Harness 将越来越重要——不只是调用云端 LLM 的薄客户端，而是真正在你的机器上自主运行的 AI 同事。

下一章见。

---

## 下一章预告

这一章讲了 Harness 的核心——循环、工具、权限、钩子、循环检测。

但一个只能跑一个 Agent、一个 Session 的 Harness 还只是原型。下一章我们看看怎么把它变成平台：多 Agent 人格、跨 Session 记忆、多源服务、生态互操作。

代码实践：[ShanClaw OSS](https://github.com/Kocoro-lab/ShanClaw)

→ [第 33 章：Building on the Harness: ShanClaw](第33章：Building-on-the-Harness-ShanClaw.md)
