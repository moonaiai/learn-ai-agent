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
| Building Effective Agents | [Building Effective Agents：从简单模式到可控 Agent](docs/building-effective-agents/building-effective-agents.md) | 基于 Anthropic 工程文章，梳理 workflow 与 agent 的边界、常见 agentic workflow 模式、autonomous agent 使用条件和 ACI 设计检查项。 |
| OpenAI Agent 实用指南 | [OpenAI 实用指南：构建 AI Agents](docs/practical-guide-building-ai-agents/practical-guide-building-ai-agents.md) | 基于 OpenAI 官方指南，梳理 agent 适用场景、model/tools/instructions/orchestration/guardrails 构件、human intervention 和生产落地检查项。 |
| ReAct 框架 | [ReAct 框架：从推理行动循环到可控 Agent](docs/react-framework/react-framework.md) | 梳理 ReAct 的推理行动循环、最小实现、prompt 结构、失败模式、评测指标和生产控制点。 |
| Tool Card 模板 | [Tool Card 模板](docs/react-framework/tool-card-template.md) | 提供工具描述模板，覆盖 Use When、Do Not Use When、输入输出 schema、错误类型、安全边界和示例。 |
| Agent 工具设计 | [Writing Effective Tools for Agents：Agent 工具设计原则](docs/writing-tools-for-agents/writing-tools-for-agents.md) | 基于 Anthropic 工程文章，梳理面向 agent 的工具粒度、命名空间、返回上下文、工具说明和 eval 迭代方法。 |
| Agent Evaluation Harness | [Agent Evaluation Harness：从感觉评估到可复现评估](docs/agent-evaluation-harness/agent-evaluation-harness-guide.md) | 基于 AgentGuide 原文沉淀 Agent 评估基础设施，梳理 task、trial、transcript、grader、report、工具选型、CI 集成和落地检查项。 |
| Context Engineering 实践技巧 | [长文深度解析：大模型的上下文陷阱与 6 大修复技巧](docs/context-engineering/context-engineering.md) | 梳理上下文中毒、干扰、混淆、冲突等失效模式，以及 offload、pruning、summarization、quarantine 等修复技巧。 |
| Context Engineering 2.0 | [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md) | 基于论文梳理上下文工程的发展脉络、关键概念、阶段框架、上下文采集/管理/使用方法，以及对 Agent 系统的启发。 |
| Build Agent Context Engineering | [Agent 架构综述：从 Prompt 到上下文工程构建 AI Agent](docs/build-agent-context-engineering/build-agent-context-engineering.md) | 原文资源本地化，覆盖结构化提示词、上下文工程、RAG、工具函数、Agent 规划与多 Agent。 |

## 学习路径

这个仓库会按 AI Agent 工程能力的成长路线持续补齐内容。当前已沉淀十份文档，后续新增文档后，会把对应节点回填到这张路线图中。

| 阶段 | 学习主题 | 需要掌握的问题 | 当前状态 |
|---:|---|---|---|
| 1 | LLM 应用基础 | LLM、Prompt、Token、结构化输出、Function Calling 分别解决什么问题。 | 待沉淀 |
| 2 | Agent 基础模型 | Agent loop 如何运转，模型、工具、状态和控制流如何配合。 | 已沉淀：[12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md)、[ReAct 框架：从推理行动循环到可控 Agent](docs/react-framework/react-framework.md) |
| 3 | Tool Calling 与工具系统 | Tool schema 如何设计，工具权限、失败、重试和审计如何处理。 | 已沉淀：[Tool Card 模板](docs/react-framework/tool-card-template.md)、[Writing Effective Tools for Agents：Agent 工具设计原则](docs/writing-tools-for-agents/writing-tools-for-agents.md) |
| 4 | Context Engineering | 什么信息应该进入上下文，如何压缩、隔离、检索和复用上下文。 | 已沉淀：[长文深度解析：大模型的上下文陷阱与 6 大修复技巧](docs/context-engineering/context-engineering.md)、[Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md)、[Agent 架构综述：从 Prompt 到上下文工程构建 AI Agent](docs/build-agent-context-engineering/build-agent-context-engineering.md) |
| 5 | Memory 与 RAG | 短期记忆、长期记忆、RAG、向量检索和知识库如何支撑 agent。 | 待沉淀 |
| 6 | Workflow 与 Multi-Agent | 什么时候用 workflow，什么时候拆 multi-agent，角色边界如何划分。 | 已沉淀：[Building Effective Agents：从简单模式到可控 Agent](docs/building-effective-agents/building-effective-agents.md) |
| 7 | Eval 与 Observability | 如何构建评测集、trace、回放、LLM-as-judge 和线上质量指标。 | 已沉淀：[Agent Evaluation Harness：从感觉评估到可复现评估](docs/agent-evaluation-harness/agent-evaluation-harness-guide.md) |
| 8 | Safety 与 Human-in-the-loop | 权限、审批、敏感操作、人工介入和安全边界如何设计。 | 已沉淀：[OpenAI 实用指南：构建 AI Agents](docs/practical-guide-building-ai-agents/practical-guide-building-ai-agents.md) |
| 9 | Production Engineering | 成本、延迟、缓存、限流、错误恢复、部署和运维如何落地。 | 已沉淀：[OpenAI 实用指南：构建 AI Agents](docs/practical-guide-building-ai-agents/practical-guide-building-ai-agents.md) |
| 10 | 项目复盘与面试表达 | 如何把 agent 项目讲成架构设计、工程取舍和业务结果。 | 待沉淀 |

### 已沉淀


1. [12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md)：先建立 Agent 工程模型，理解 prompt、context、tool call、state、control flow 和 human-in-the-loop 的关系。
2. [长文深度解析：大模型的上下文陷阱与 6 大修复技巧](docs/context-engineering/context-engineering.md)：理解长上下文并不天然可靠，重点关注上下文失效模式和修复手段。
3. [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md)：再理解上下文工程，明确上下文不是越多越好，而是要围绕当前任务做选择、压缩、隔离和复用。
4. [Agent 架构综述：从 Prompt 到上下文工程构建 AI Agent](docs/build-agent-context-engineering/build-agent-context-engineering.md)：保留原文和本地图片资源，作为从提示词、上下文工程到 Agent 规划的外部资料入口。
5. [ReAct 框架：从推理行动循环到可控 Agent](docs/react-framework/react-framework.md)：理解 Reasoning + Acting 的基础循环，并把它转成可控的工具、状态、停止条件和 trace 设计。
6. [Tool Card 模板](docs/react-framework/tool-card-template.md)：沉淀工具说明模板，帮助模型正确选择工具、理解输入输出、处理错误和遵守权限边界。
7. [Writing Effective Tools for Agents：Agent 工具设计原则](docs/writing-tools-for-agents/writing-tools-for-agents.md)：理解 tool 不是 API endpoint 的简单包装，而是需要围绕 agent 任务、上下文和 eval 持续迭代的接口。
8. [Building Effective Agents：从简单模式到可控 Agent](docs/building-effective-agents/building-effective-agents.md)：理解 workflow 与 agent 的控制权差异，并掌握 prompt chaining、routing、parallelization、orchestrator-workers、evaluator-optimizer 等常见模式的适用边界。
9. [OpenAI 实用指南：构建 AI Agents](docs/practical-guide-building-ai-agents/practical-guide-building-ai-agents.md)：从 OpenAI 官方实践视角理解 agent 的适用条件、基础构件、编排方式、guardrails、人类介入和生产检查项。
10. [Agent Evaluation Harness：从感觉评估到可复现评估](docs/agent-evaluation-harness/agent-evaluation-harness-guide.md)：理解 Agent 评估如何从手动试用变成任务、环境、轨迹、评分器、报告和 CI 门禁组成的可复现流程。

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

- **中文系统整理与原文归档并存**：既有按工程理解重新组织的中文资料，也保留外部优质原文和本地图片资源。
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
│   ├── context-engineering/
│   │   ├── context-engineering.md
│   │   └── figures/
│   ├── context-engineering-2.0-pdf/
│   │   ├── context_engineering_2_cn_notes.md
│   │   └── context_engineering_2_figures/
│   ├── react-framework/
│   │   ├── react-framework.md
│   │   └── tool-card-template.md
│   ├── writing-tools-for-agents/
│   │   └── writing-tools-for-agents.md
│   ├── building-effective-agents/
│   │   ├── building-effective-agents.md
│   │   └── figures/
│   ├── practical-guide-building-ai-agents/
│   │   ├── practical-guide-building-ai-agents.md
│   │   └── figures/
│   ├── agent-evaluation-harness/
│   │   └── agent-evaluation-harness-guide.md
│   └── build-agent-context-engineering/
│       ├── build-agent-context-engineering.md
│       └── images/
└── agents/
    └── writing-skill/
```

## 后续计划

- 增加 Memory、RAG 等专题整理，并继续补充更细的 Multi-Agent 工程案例。
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
