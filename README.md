# Learn AI Agent

> 面向 AI Agent 工程实践的中文学习资料库，系统整理 Agent 设计原则、上下文工程、可靠性、状态管理、工具调用和生产落地方法。

## 项目定位

`learn-ai-agent` 不是零散资料收藏夹，而是一个围绕 **AI Agent 工程能力** 建立的系统化学习仓库。

仓库重点关注：

- Agent 为什么不是简单的 Prompt + Tool。
- 一个可靠 Agent 系统应该如何组织 prompt、context、tool call、state 和 control flow。
- 上下文工程如何从 prompt engineering 扩展到 memory、RAG、multi-agent 和长期任务。
- 如何把论文、开源项目和实践经验整理成可复盘、可迁移的工程知识。

这份资料更偏工程视角：少讲概念口号，多讲设计边界、实现结构、取舍依据和落地检查项。

## 适合人群

- 正在系统学习 AI Agent / LLM 应用开发的工程师。
- 希望理解 Agent 架构、上下文工程、工具调用和状态管理的开发者。
- 准备 AI Agent 工程师、LLM 应用工程师、RAG 工程师相关面试的人。
- 已经使用过 Claude Code、Codex、Cursor、LangGraph、Dify、Coze 等工具，但希望进一步理解底层设计的人。
- 想把外部论文、开源项目和工程经验整理成长期知识库的人。

## 当前内容

| 主题 | 文档 | 核心内容 |
|---|---|---|
| 12-Factor Agents | [12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md) | 从 agent loop、上下文窗口、工具调用、控制流、暂停恢复、人类介入和无状态 reducer 等角度，总结可靠 Agent 的 12 条工程原则。 |
| Context Engineering 2.0 | [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md) | 基于论文梳理上下文工程的发展脉络、关键概念、阶段框架、上下文采集/管理/使用方法，以及对 Agent 系统的启发。 |

## 学习路径

这个仓库会按 AI Agent 工程能力的成长路线持续补齐内容。当前只沉淀了其中两个关键主题，后续新增文档后，会把对应节点回填到这张路线图中。

| 阶段 | 学习主题 | 需要掌握的问题 | 当前状态 |
|---:|---|---|---|
| 1 | LLM 应用基础 | LLM、Prompt、Token、结构化输出、Function Calling 分别解决什么问题。 | 待沉淀 |
| 2 | Agent 基础模型 | Agent loop 如何运转，模型、工具、状态和控制流如何配合。 | 已沉淀：[12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md) |
| 3 | Tool Calling 与工具系统 | Tool schema 如何设计，工具权限、失败、重试和审计如何处理。 | 待沉淀 |
| 4 | Context Engineering | 什么信息应该进入上下文，如何压缩、隔离、检索和复用上下文。 | 已沉淀：[Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md) |
| 5 | Memory 与 RAG | 短期记忆、长期记忆、RAG、向量检索和知识库如何支撑 agent。 | 待沉淀 |
| 6 | Workflow 与 Multi-Agent | 什么时候用 workflow，什么时候拆 multi-agent，角色边界如何划分。 | 待沉淀 |
| 7 | Eval 与 Observability | 如何构建评测集、trace、回放、LLM-as-judge 和线上质量指标。 | 待沉淀 |
| 8 | Safety 与 Human-in-the-loop | 权限、审批、敏感操作、人工介入和安全边界如何设计。 | 待沉淀 |
| 9 | Production Engineering | 成本、延迟、缓存、限流、错误恢复、部署和运维如何落地。 | 待沉淀 |
| 10 | 项目复盘与面试表达 | 如何把 agent 项目讲成架构设计、工程取舍和业务结果。 | 待沉淀 |

### 已沉淀主题的阅读顺序

当前可以先从两篇已完成文档开始：

1. [12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md)：先建立 Agent 工程模型，理解 prompt、context、tool call、state、control flow 和 human-in-the-loop 的关系。
2. [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md)：再理解上下文工程，明确上下文不是越多越好，而是要围绕当前任务做选择、压缩、隔离和复用。

### 项目迁移检查

读完任何一个主题后，都可以结合自己的业务场景做一次迁移检查：

| 问题 | 思考方向 |
|---|---|
| Agent 负责什么任务 | 是否能控制在 3 到 10 个关键步骤内。 |
| 输入上下文来自哪里 | 用户请求、历史事件、RAG、工具结果、记忆、外部系统状态。 |
| 模型输出什么 | 是否是可解析、可校验、可审计的结构化动作。 |
| 工具如何执行 | 哪些同步执行，哪些需要审批，哪些进入异步队列。 |
| 状态如何保存 | 是否能通过事件线程恢复、重放和审计。 |
| 错误如何处理 | 是否能摘要化写回上下文，并设置重试上限。 |

## 内容特色

- **中文系统整理**：不是逐句翻译，而是按工程理解重新组织结构。
- **保留原图与关键结构**：重要图示已本地化保存，方便离线阅读和长期维护。
- **强调工程落地**：每篇文档都尽量包含设计背景、核心概念、实现含义、风险边界和检查表。
- **面向长期复盘**：文档结构适合反复查阅，也适合后续扩展成面试材料、项目设计文档或内部分享。

## 仓库结构

```text
learn-ai-agent/
├── README.md
├── index.md
├── docs/
│   ├── 12-factor-agents/
│   │   ├── 12-factor-agents-principles.md
│   │   └── figures/
│   └── context-engineering-2.0-pdf/
│       ├── context_engineering_2_cn_notes.md
│       └── context_engineering_2_figures/
└── agents/
    └── writing-skill/
```

## 后续计划

- 增加 Agent Loop、Tool Calling、Memory、Multi-Agent、RAG、Eval 等专题整理。
- 补充优秀开源 Agent 项目的架构阅读材料。
- 沉淀 AI Agent 面试问答和项目表达材料。
- 将学习资料逐步组织成“概念 -> 设计原则 -> 工程实践 -> 项目复盘”的完整路径。

## 阅读建议

学习 Agent 不建议只记框架 API。更重要的是建立几条长期稳定的工程判断：

- 上下文不是越多越好，而是要和当前决策强相关。
- 模型输出不应直接等于业务副作用。
- 状态要能保存、恢复、审计和重放。
- 高风险动作要能在执行前被人类或确定性规则截停。
- 小范围、可验证的 agent 更容易稳定落地。

如果能用这些问题审视自己的系统，AI Agent 就不再只是一个聊天机器人，而是一种可以进入真实软件流程的工程组件。
