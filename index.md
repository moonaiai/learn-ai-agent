# Learn AI Agent

面向 AI Agent 工程实践的中文知识库。

## 文档

| 主题 | 文档 | 摘要 |
|---|---|---|
| 12-Factor Agents | [12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md) | 从 agent loop、上下文窗口、控制流、状态恢复和人类介入等角度，总结 12-Factor Agents 的工程化设计原则。 |
| Building Effective Agents | [Building Effective Agents：从简单模式到可控 Agent](docs/building-effective-agents/building-effective-agents.md) | 梳理 workflow 与 agent 的控制权差异、常见 agentic workflow 模式、autonomous agent 使用条件和 ACI 设计检查项。 |
| OpenAI Agent 实用指南 | [OpenAI 实用指南：构建 AI Agents](docs/practical-guide-building-ai-agents/practical-guide-building-ai-agents.md) | 梳理 agent 适用场景、model/tools/instructions/orchestration/guardrails 构件、human intervention 和生产落地检查项。 |
| ReAct 框架 | [ReAct 框架：从推理行动循环到可控 Agent](docs/react-framework/react-framework.md) | 梳理 ReAct 的推理行动循环、最小实现、prompt 结构、失败模式、评测指标和生产控制点。 |
| Tool Card 模板 | [Tool Card 模板](docs/react-framework/tool-card-template.md) | 提供工具描述模板，覆盖适用边界、输入输出 schema、错误类型、安全要求和调用示例。 |
| Agent Evaluation Harness | [Agent Evaluation Harness：从感觉评估到可复现评估](docs/agent-evaluation-harness/agent-evaluation-harness-guide.md) | 梳理 Agent 评估中的 task、trial、transcript、grader、report、工具选型、CI 集成和落地检查项。 |
| Context Engineering 2.0 | [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md) | 从论文视角梳理上下文工程的定义、历史阶段、设计框架和 agent 系统中的实践意义。 |

## 写作规范

项目级写作规范位于 [agents/writing-skill](agents/writing-skill/SKILL.md)。后续新增文档应保持客观、结构化、工程化的中文表达，并优先使用本地图片资源。
