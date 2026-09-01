# DeepSeek-Reasonix 缓存命中率优化机制

> 基于源码阅读

## TL;DR

- DeepSeek 的缓存规则是**前缀字节完全匹配**：请求体从哪个字节开始跟上次不一样，那个字节之后全部按未命中价计费（贵 50~120 倍）。
- 真正决定"字节是否一致"的只有两件事：**工具列表顺序必须稳定**、**历史只追加，压缩不重写**。
- 剩下都是护栏，防止这两条被后续改动悄悄破坏。

---

## Q0：DeepSeek 的缓存到底怎么运作，为什么"字节"这么重要？

它是一个隐式（implicit）缓存：没有 Anthropic 那种显式 `cache_control` 断点，服务端按最长公共前缀在磁盘上匹配缓存。命中的 token 单价是未命中的 **1/50 ~ 1/120**（`deepseek-chat` ¥0.02 vs ¥1；`deepseek-reasoner` ¥0.025 vs ¥3，见 `internal/config/pricing.go`）。

推论只有一条：只要请求体从某个字节开始和上次不一样，那个字节**之后全部**变成 miss。客户端唯一能做的事，就是别在前缀里制造不必要的字节抖动——下面六个问题，都是这条原则在代码里的具体落地。

---



## Q1：为什么工具列表必须强制排序？

MCP 工具是异步注册的，两次启动的顺序可能不一样（这次 `file → git → bash`，下次 `git → file → bash`）。工具集合完全没变，但 `tools` 数组的字节顺序变了——它排在 `system` 之后、`messages` 之前，DeepSeek 按前缀字节匹配缓存，从这里开始整个前缀作废。用户的直观感受是："我今天就重启了一下 agent，代码一行没改，怎么这轮对话突然全价了？"

解法很直接：序列化前按工具名称强制排序（不依赖注册顺序），JSON Schema 本身也做递归规范化（统一空参数写法、排序 `required` 数组），保证不同来源、不同顺序的工具最终产出完全相同的字节。

```go
// internal/tool/tool.go:611-621
sort.Strings(names)   // 无论发现顺序如何，永远按字母序序列化
```

📄 `internal/tool/tool.go`、`internal/provider/schema_canonicalize.go`

---



## Q2：为什么协议字段要设计成"能不带就不带"？

用户中途 `/effort disabled` 关掉了思考模式。如果客户端为了"协议看起来统一"，机械地给历史里每条 assistant 消息都补上或清空 `reasoning_content` 这类字段，那么**这次操作之前的全部历史**在字节层面都会整体变一遍——聊天内容一个字没改，却要重新计费。

解法是把这类字段做成指针：只在真正需要时（如带过推理内容的消息）才带 key，其余消息严格不多一个字节。


| 字段                         | 只在什么情况下出现                                               |
| -------------------------- | ------------------------------------------------------- |
| `ReasoningContent *string` | thinking 模式下、且该消息真带过推理内容（丢弃会打穿 thinking-on→off 混合会话的前缀） |
| `Prefix bool,omitempty`    | 仅 DeepSeek Beta 截断续写                                    |
| `Name *string`（tool 消息）    | 严格后端要求必须存在 key                                          |


📄 `internal/provider/openai/openai.go`

---



## Q3：为什么历史清洗函数总是先判断"要不要动"，而不是直接处理？

每轮请求前，代码都要跑一遍"历史体检"——补齐没配对的 tool_call、清掉本地专用字段。这类函数如果图省事，无脑重建一份新的消息切片，很容易在重建过程中带入顺序抖动或字段差异——结果是**逻辑上完全健康、什么都不需要改的会话，也被意外改变了字节**。这种回归最难排查，表现为"偶尔莫名其妙不命中"，而不是稳定复现。

所以 `NormalizeMessages` / `ModelMessages` / `ProjectionMessages` 统一遵循同一模式：先扫一遍判断是否真的需要改动，不需要就原样返回同一个 slice，一个字节都不碰。

```go
// internal/provider/provider.go:297-303
// A well-formed history ... returns the input slice unchanged (same backing
// array, zero allocation). This keeps the prefix-cache key stable ...
```

📄 `internal/provider/provider.go`、`internal/provider/projection.go`

---



## Q4：为什么压缩上下文靠"一次性检查点"，而不是随时顺手瘦身？

长会话上下文快顶到窗口上限了。如果做法比较粗放——隔三差五就把老消息模糊压缩一下（"软压缩"），那么每次压缩都等于把已经攒了几十万 token、命中率很高的历史**整个改写**一遍。更糟的是压缩完没跑几轮又顶到阈值，于是再压缩一次——用户看到的是"越用越贵、越压缩越贵"，本该省钱的动作反而成了缓存头号杀手。

Reasonix 的做法很克制：触发阈值高且唯一（`compact_ratio = 0.85`）；原始 `Session.Messages` 全程只追加、从不重写，真正的压缩结果是一份独立的旁路 "projection"；固定前缀 + 一段摘要 + 最近原文尾巴的三段式结构，让压缩点之后的新内容仍可继续追加式缓存；折叠必须省下 ≥400 token 才值得触发，避免"为省小钱先花一次大 miss"。

```go
// internal/agent/projection.go:52-53
// The canonical transcript in Session.Messages is never replaced.
```

📄 `internal/agent/compact.go`、`projection.go`、`compact_commit.go`

---



## Q5：命中率突然掉了，怎么知道是谁的锅？

某轮对话突然从命中价跳到未命中价。是自己刚 `/compact` 了？回退（rewind）了一条消息？装了新 MCP 插件导致工具列表变了？还是系统 bug？没有诊断信息只能靠猜，而且这类回归很容易在后续改动里被悄悄引入却没人发现。

解法是每轮请求前，对影响前缀的部分（system + 排序后的 tools）算一次哈希快照，跟上一轮 diff，再结合会话侧记录的具体改写原因（压缩、snip、rewind、guardian merge…）一起上报，形成可观测的诊断事件，还附带会话级累计命中率（不因单轮波动失真）。

📄 `internal/agent/cache_shape.go`（`CaptureShape` / `CompareShape`）、`internal/event/event.go`（`CacheDiagnostics`）

---



## Q6：会话晾了很久之后 resume，为什么不顺手清理一下历史？

中午吃饭，下午回来 `--resume` 接着写。如果系统觉得"闲置这么久，缓存肯定过期了，不如顺便清理一下"，这个"善意"的清理动作反而可能作废一份**实际上还热着**的服务端缓存，让用户莫名其妙付了全价——这类自作聪明的优化，往往比什么都不做伤害更大。

解法是按 vendor 真实缓存保留时长判断：DeepSeek 磁盘缓存能扛数小时到数天，默认 TTL 定为 24h（远长于 DashScope/Anthropic 的 5 分钟）；resume 时只记录 warm/cold 状态，从不主动改写历史。

```
DeepSeek Context Caching on Disk: 数小时到数天 → 默认 TTL 24h
DashScope / Anthropic:                    5 分钟
```

📄 `internal/config/cache_policy.go`、`internal/control/projection_bind.go`

---



## 一张图看完整个链条

```
稳定的系统提示词 + 工具排序规范化 + 消息"零拷贝"清洗
+ Wire 字段最小变化 + 历史 append-only（压缩旁路化） + 感知 vendor TTL
                        │
                        ▼
        请求前缀字节 ≈ 上一次请求的前缀字节
                        │
                        ▼
              DeepSeek 磁盘前缀缓存命中
```

---



## 代码索引


| 主题                      | 文件                                                                      |
| ----------------------- | ----------------------------------------------------------------------- |
| 工具排序与 Schema 规范化        | `internal/tool/tool.go`、`internal/provider/schema_canonicalize.go`      |
| Wire 层字节稳定性技巧           | `internal/provider/openai/openai.go`                                    |
| 会话历史零拷贝清洗               | `internal/provider/provider.go`、`internal/provider/projection.go`       |
| 历史 append-only / 压缩旁路投影 | `internal/agent/projection.go`、`compact.go`、`compact_commit.go`         |
| 前缀诊断                    | `internal/agent/cache_shape.go`、`internal/event/event.go`               |
| Vendor 缓存 TTL / 冷热恢复    | `internal/config/cache_policy.go`、`internal/control/projection_bind.go` |
| 命中/未命中定价                | `internal/config/pricing.go`、`internal/billing/quote.go`                |


---

