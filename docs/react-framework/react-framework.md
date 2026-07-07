# ReAct 框架：从推理行动循环到可控 Agent

资料来源：[AgentGuide/docs/01-theory/04-react-framework.md](https://github.com/adongwanai/AgentGuide/blob/main/docs/01-theory/04-react-framework.md)

## 阅读目标

关注三个问题：

1. ReAct 如何把模型推理和工具行动组织成 agent loop。
2. 为什么真实工程不能只依赖模型不断“思考”。
3. 如何为 ReAct Agent 设计工具、状态、停止条件、错误恢复和 trace。

核心结论是：ReAct 是理解 Agent loop 的基础框架，但生产系统的关键不在于让模型输出更长的推理过程，而在于把模型决策约束成可解析、可执行、可审计、可中断的动作循环。

## 名词解释

| 名词 | 解释 | 简单例子 |
|---|---|---|
| ReAct | Reasoning + Acting 的缩写，让模型在推理和行动之间交替推进任务。 | 模型判断需要查资料，调用搜索工具，再根据搜索结果继续判断。 |
| Reasoning | 模型对当前任务、已有证据和下一步动作的判断过程。 | “需要先确认论文来源，再比较方法差异”。 |
| Acting | 模型选择工具或输出最终答案的动作阶段。 | 调用 `search_papers`，或返回 final answer。 |
| Observation | 工具调用后的结果，被写回上下文供模型继续决策。 | 搜索工具返回 5 篇论文标题、年份和链接。 |
| Agent loop | 模型决定下一步、代码执行动作、结果回到上下文的循环。 | 最多执行 6 步，每一步都记录工具、参数和结果摘要。 |
| Trace | 对一次 agent 执行过程的结构化记录，用于审计、调试和复盘。 | 第 2 步调用了 `search`，参数是某个 query，结果摘要是找到 5 篇论文。 |
| Tool Card | 描述工具用途、适用场景、输入输出、错误和权限的结构化说明。 | `search_papers` 的 Use When、Input Schema、Errors 和 Example。 |

## 1. 基本模式

ReAct 的最小思想是：模型不要一次性直接给答案，而是在“判断下一步”和“执行下一步”之间反复切换。

典型文本形态如下：

```text
Question: ...
Thought: I need to search for evidence.
Action: search(query="...")
Observation: ...
Thought: The evidence is enough.
Final Answer: ...
```

这个结构适合理解概念，但真实系统不建议完整保存或展示模型的全部 `Thought`。更稳妥的做法是保存可审计摘要，记录模型为什么需要某个动作，但不把长推理链当成业务事实。

```json
{
  "step": 2,
  "action": "search",
  "args": {
    "query": "agentic rag evaluation"
  },
  "reason_summary": "Need external evidence before comparing methods.",
  "observation_summary": "Found 5 papers from 2024-2025."
}
```

这里的重点不是保存“模型想了什么”，而是保存“系统为什么执行了这一步，以及这一步得到了什么结果”。

## 2. 最小实现骨架

ReAct Agent 可以先从一个普通循环开始实现。模型只负责返回结构化决策，代码负责校验工具、执行工具、记录 trace 和判断是否结束。

```python
def react(task, model, tools, max_steps=6):
    trace = []
    observations = []

    for step in range(max_steps):
        prompt = build_prompt(task, tools, observations)
        decision = model.generate_json(prompt)

        if decision["type"] == "final":
            return {
                "answer": decision["answer"],
                "trace": trace,
                "status": "completed",
            }

        tool_name = decision["tool"]
        if tool_name not in tools:
            obs = {"ok": False, "error": "unknown_tool"}
        else:
            args = decision.get("args", {})
            tool = tools[tool_name]
            obs = tool(**args)

        observations.append(obs)
        trace.append({
            "step": step + 1,
            "tool": tool_name,
            "args": decision.get("args", {}),
            "observation": summarize(obs),
        })

    return {
        "answer": None,
        "trace": trace,
        "status": "max_steps_exceeded",
    }
```

这段代码里有几个生产系统需要继续补强的点：

| 维度 | 检查项 | 期望状态 |
|---|---|---|
| 结构化输出 | 模型输出是否有 schema 校验。 | 无法解析或字段非法时进入错误恢复，而不是继续执行。 |
| 工具注册 | 工具名是否来自白名单。 | 未注册工具返回 `unknown_tool`，不会动态执行任意代码。 |
| 停止条件 | 是否有最大步数和 final gate。 | 循环不会无限搜索、点击或重试。 |
| Trace | 是否记录工具、参数、结果摘要和状态。 | 失败后能定位哪一步造成偏差。 |
| 错误恢复 | 工具失败后是否可被模型理解。 | 错误被摘要化写回 observation，而不是泄露冗长堆栈。 |

## 3. Prompt 结构

ReAct 的 prompt 应尽量把任务、工具、历史 observation 和输出格式分开写清楚。模型要知道：它只能使用哪些工具，什么时候应该停止，缺少证据时应该如何表达。

```text
You are an agent that solves the task by calling tools.

Rules:
- Use only the listed tools.
- Stop when enough evidence is collected.
- If evidence is missing, say what is missing.
- Never fabricate tool results.

Task:
{task}

Tools:
{tool_cards}

Previous observations:
{observations}

Return JSON:
{
  "type": "tool_call | final",
  "tool": "tool name or null",
  "args": {},
  "answer": "final answer or null",
  "reason_summary": "short auditable reason"
}
```

这里的 `reason_summary` 应保持短句化，用于解释动作选择，而不是要求模型展开完整思维链。工程上更重要的是可审计、可压缩、可回放。

## 4. Tool Card 很重要

ReAct 失败常常不是模型不会推理，而是工具描述没有给出足够明确的使用边界。工具如果只写“搜索论文”或“查询订单”，模型很难判断什么时候该用、什么时候不该用、失败后应该怎么恢复。

每个工具至少应写清楚：

- 什么时候用。
- 什么时候不要用。
- 输入 schema。
- 输出 schema。
- 错误类型。
- 权限等级。
- 示例。

可参考：[Tool Card 模板](tool-card-template.md)。

## 5. 常见失败模式

| 失败 | 现象 | 修复 |
|---|---|---|
| 无限循环 | 一直搜索、重复点击或反复调用同一工具。 | 设置最大步数、重复动作检测和相同错误上限。 |
| 工具选择错 | 本该查数据库却搜索网页。 | 在 Tool Card 中补充 Use When 和 Do Not Use。 |
| Observation 过长 | 工具返回内容淹没关键信息。 | 工具层做分页、摘要、截断和引用保留。 |
| 过早 final | 证据不足就回答。 | 增加 evidence gate、引用检查和缺失信息表达规则。 |
| 幻觉工具结果 | 没调用工具却声称已经查到。 | final answer 必须引用已有 observation 或 trace。 |
| 高风险动作失控 | 自动付款、删除、提交、发外部消息。 | 引入 permission tier 和 human-in-the-loop。 |

这些失败模式说明，ReAct 的稳定性主要来自循环外的工程约束，而不是 prompt 里的“请认真思考”。

## 6. ReAct 与其他 Agent 模式

| 模式 | 适合场景 | 主要风险 |
|---|---|---|
| ReAct | 短任务、信息查找、工具反馈快、下一步依赖 observation 的任务。 | 容易局部贪心、重复调用工具或过早结束。 |
| Plan-and-Execute | 长任务、步骤较明确但执行中需要调整的任务。 | 初始计划可能过时，计划和执行状态可能脱节。 |
| Reflection | 需要复盘、修正和自检的任务。 | 反思本身也可能幻觉，不能替代外部证据。 |
| Graph workflow | 状态分支明确、需要恢复、审批和确定性控制的任务。 | 设计成本更高，需要预先建模流程边界。 |

工程上可以混合使用这些模式。确定性流程适合放在 graph 或 workflow 中，开放决策点再嵌入小范围 ReAct。

## 7. 实践中它们到底是怎么被用起来的

一个常见的疑惑是：ReAct 和 Plan-and-Execute 是不是都只是 prompt 工程？答案是**决策靠 prompt，工程化靠代码**。模型“下一步该干嘛”“计划怎么拆”的判断来自 prompt，但真正让它们能上生产的，是 prompt 之外的一圈工程约束。这一圈约束的比重和形态，决定了两者的本质差异。

### ReAct：一个“带 ReAct 属性的 Agent” + 工程控制点

ReAct 在实践中更像一个**拥有 ReAct 属性的 Agent**：它的核心是一个 `Thought → Action → Observation` 的单步循环，模型每步根据上一步的 observation 重新决策。这个循环本身很轻，稳定性几乎全部来自循环外的工程控制点：

| 工程控制点 | 作用 |
|---|---|
| 结构化输出 + schema 校验 | 模型决策可解析，非法时进错误恢复而非继续执行。 |
| 工具注册表 / 白名单 | 只能调用已注册工具，不会动态执行任意代码。 |
| 最大步数 + 重复动作检测 | 防止无限搜索、反复点击、重复调用同一工具。 |
| 证据门禁 / final gate | 证据不足不能过早结束。 |
| 权限分级 + human-in-the-loop | 高风险动作（付款、删除、外发）需确认。 |
| Trace | 每步的工具、参数、结果摘要可审计、可回放。 |

换句话说，ReAct 的“Agent 气质”很重：开放决策、临场判断、走一步看一步。工程要做的是把这些控制点补齐，让一个本来容易失控的循环变得可解析、可执行、可中断、可审计。**少了这些控制点，ReAct 就只是 prompt；补齐了，它才是一个生产可用的 Agent。**

### Plan-and-Execute：更像一个 Workflow 模式

Plan-and-Execute 在实践中更接近一个 **Workflow**：先用 planner 产出完整步骤序列，再由 executor 逐步执行，偏差时 re-plan。它的核心不是单步循环，而是 planner / executor 两个独立角色之间的**显式状态流转**：

| Workflow 特征 | 在 Plan-and-Execute 中的体现 |
|---|---|
| 有显式的计划产物 | planner 输出步骤序列，是可 review、可 checkpoint 的对象。 |
| 状态分离 | 计划、进度、执行结果三套状态需要同步，这是代码逻辑而非 prompt。 |
| 可并行 / 可中断 | 独立子步骤可并行执行，失败可从 checkpoint 恢复。 |
| Re-plan 是控制流 | 执行失败或偏差触发重新规划，是编排层的条件分支。 |
| 执行器上下文聚焦 | executor 每步只看局部，避免长上下文稀释。 |

这也就是为什么很多框架（LangGraph、LlamaIndex workflow）会把 Plan-and-Execute 画成 graph 节点——它已经不只是 prompt，而是一个**有状态的控制流图**。它的“Workflow 气质”很重：步骤大体可预判、链路长、需要可审计和可恢复。

### 一句话对照

> **ReAct 是“带工程控制点的 Agent”，Plan-and-Execute 是“带 re-plan 能力的 Workflow”。**

两者的差异主要不在 prompt，而在编排代码：ReAct 是单循环 + 约束；Plan-and-Execute 是 planner/executor 双角色 + 显式状态 + re-plan，本质上更接近一个 workflow 引擎。判断口诀：**“能不能先把步骤写下来”能写下来 → Plan-and-Execute 为主；写不下来、必须看反馈 → ReAct 为主。** 链路越长、越可预判，越偏向 Plan-and-Execute；反馈越即时、环境越未知，越偏向 ReAct。

## 8. 评测 ReAct Agent

ReAct Agent 至少应记录以下指标：

| 指标 | 用途 |
|---|---|
| 任务成功率 | 判断 agent 是否真正完成用户目标。 |
| 平均步数 | 观察是否存在过度搜索、过度重试或流程过长。 |
| 工具调用成功率 | 判断工具 schema、参数生成和工具稳定性是否足够。 |
| 重复动作次数 | 发现循环和局部贪心问题。 |
| 证据引用准确率 | 检查 final answer 是否基于 observation。 |
| 高风险动作拦截率 | 验证权限、审批和安全边界是否生效。 |
| 成本和延迟 | 衡量 agent loop 对用户体验和系统资源的影响。 |

如果这些指标没有被记录，ReAct Agent 的调优通常只能依赖个案感受，很难稳定复盘。

## 9. 面试表达

可以这样概括 ReAct：

> 我会把 ReAct 看成 Agent loop 的基础模式，但不会只依赖 prompt。工程实现里会加工具注册表、结构化输出、最大步数、重复动作检测、权限确认和 trace。对需要稳定性的业务流程，我会优先用 graph 或 workflow 承载确定步骤，只在开放决策点使用 ReAct。

这个表达的重点是把框架概念翻译成工程控制点：工具、状态、停止条件、错误恢复、权限和可观测性。

## 关键结论

1. ReAct 的价值在于把“下一步判断”和“工具执行结果”放进同一个循环。
2. 生产系统不要依赖完整思维链，而应保存短的、可审计的 `reason_summary` 和 observation 摘要。
3. Tool Card 决定了模型能否正确选择工具，也决定了失败恢复质量。
4. ReAct 需要最大步数、重复动作检测、证据门禁、权限分级和 human-in-the-loop。
5. 稳定业务流程不应全部交给 ReAct，确定性步骤更适合由 workflow 或 graph 承载。
6. 实践中 ReAct 是“带工程控制点的 Agent”，Plan-and-Execute 是“带 re-plan 能力的 Workflow”；两者差异主要在编排代码，而非 prompt。

## 延伸阅读

- [ReAct: Synergizing Reasoning and Acting in Language Models](https://arxiv.org/abs/2210.03629)
- [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [LangGraph](https://github.com/langchain-ai/langgraph)
- [OpenAI Swarm](https://github.com/openai/swarm)
