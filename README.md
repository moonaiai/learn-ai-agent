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
| Transformer Self-Attention | [Transformer Self-Attention：Q/K/V 与注意力怎么算](docs/transformer/01-transformer-self-attention.md) | 基于 The Illustrated Transformer 沉淀，拆解 Self-Attention 公式、Q/K/V 工程含义、Multi-Head、Masked、位置编码、复杂度与面试速答卡；原文图片已本地化。 |
| Attention Is All You Need | [Attention Is All You Need：Transformer 与纯注意力架构](docs/transformer/02-attention-is-all-you-need.md) | 基于 Transformer 原论文沉淀，梳理用注意力取代 RNN/CNN 的动机、Scaled Dot-Product 缩放原理、Multi-Head 与三种注意力接线、Position-wise FFN、正余弦位置编码、复杂度对比、warmup 与 label smoothing 训练配方、WMT 翻译与句法分析结果，以及工程实现检查清单。 |
| Decoder-Only 与 GPT | [GPT vs BERT：为什么 LLM 都用 Decoder-Only](docs/gpt/01-decoder-only-vs-encoder-decoder.md) | 基于 The Illustrated GPT-2 沉淀，对比 Encoder-Only / Decoder-Only / Encoder-Decoder 三种拓扑，解释 BERT 的 MLM 与 GPT 的 Next Token Prediction 分歧，并梳理 Decoder-Only 成为主流 LLM 的工程原因。 |
| Tokenization | [Tokenization：BPE / WordPiece / Unigram 怎么选](docs/tokenization/01-bpe-wordpiece-unigram.md) | 梳理 tokenization 动机、词级/字符级/子词级粒度取舍、BPE 自底向上合并、WordPiece 似然比合并、Unigram 自顶向下剪枝、SentencePiece 统一接口、tiktoken / rustbpe 工业实现、特殊 token 与词表大小权衡。 |
| 推理采样参数 | [推理采样参数：temperature / top_p / top_k](docs/sampling/01-temperature-top-p-top-k.md) | 拆解 Greedy、Beam Search、Sampling、Temperature 缩放、Top-k 硬截断、Top-p Nucleus 自适应集合、min_p / typical_p / contrastive 等变体、Repetition Penalty、HF generate 与 vLLM logits processor、Speculative Decoding 与 sampling 的严格对齐。 |
| KV Cache | [KV Cache：自回归推理的工程加速](docs/kv-cache/01-kv-cache-inference.md) | 从自回归推理逐步展开推导 KV Cache 可复用性，给出 QK^T 增量计算与显存公式，对比 MHA / MQA / GQA 显存，详解 PagedAttention（vLLM）的分页与 prefix sharing、FlashAttention 兼容、Quantized KV Cache / Offload 等进阶优化。 |
| LoRA | [LoRA：低秩适配微调](docs/lora/01-lora-low-rank-adaptation.md) | 拆解全量微调成本、低秩假设与内在维度、LoRA 数学形式 W' = W + α/r · B·A、初始化约定、target_modules / alpha / rank 选择、merge 推理、与 Adapter / Prefix Tuning 的对比、AdaLoRA / DoRA 变体与 Hugging Face PEFT 工业实践。 |
| QLoRA | [QLoRA：把 65B 微调压进单张 24GB 显卡](docs/qlora/01-qlora-quantized-lora.md) | 基于 QLoRA 论文沉淀 4-bit NormalFloat + Double Quantization + Paged Optimizers + LoRA 的完整方案，对比 FP16/LoRA/QLoRA 的显存与质量，覆盖 bitsandbytes 4-bit 加载配置、Unsloth/Axolotl 工程实践与面试速答卡。 |
| RoPE 旋转位置编码 | [RoPE：旋转位置编码与相对注意力](docs/positional-encoding/01-rope-relative-position.md) | 基于 RoFormer 论文沉淀，拆解旋转角度与位置成正比、复数/旋转矩阵公式、相对注意力内积构造、远程衰减性质、长度外推（PI / NTK-aware / YaRN）、与 Flash Attention / KV Cache 的兼容性，以及 Sinusoidal / Learned / ALiBi / RoPE 的对比。 |
| Embedding 选型 | [Embedding 模型选型：从 MTEB 排名到工程落地](docs/embedding/01-embedding-model-selection.md) | 梳理 Embedding 模型输入输出、Bi-Encoder vs Cross-Encoder、对称 vs 非对称检索、MTEB 8 类任务、闭源/开源模型分层、维度选择、Matryoshka 压缩、指令调优 Embedding、中文场景、自家评测方法与工程落地清单。 |
| Karpathy Zero to Hero | [Karpathy Zero to Hero：讲座列表与学习顺序](docs/zero-to-hero/01-karpathy-zero-to-hero-learning-path.md) | 整理 Andrej Karpathy "Neural Networks: Zero to Hero" 视频系列 8 讲的标题、时长、YouTube 链接、原文简介、配套代码仓库（micrograd / makemore / ng-video-lecture / minbpe），以及按页面原样标注的依赖关系。 |
| Loop Engineering | [Loop Engineering：Karpathy Loop 与让它快 5 倍的双层循环](docs/loop-engineering/loop-engineering-karpathy-method.md) | 基于 codila 文章沉淀 Loop Engineering，拆解 loop 的 verifier / state / stop condition 三要素、是否需要 loop 的四项检查、Karpathy AutoResearch 三文件约束、automation / skill / sub-agents / connectors / verifier 五个构件，以及 Bilevel Autoresearch 在外层套 loop 实现 5 倍提升的架构原因；并结合 AutoResearch 源码精读 `prepare.py` 不可篡改的 BPB 闸门、`train.py` 的现代基线与 MuonAdamW 优化器、`program.md` 作为 skill 的实验协议。 |
| Agent Memory 综述 | [Agent Memory 综述：Forms、Functions 与 Dynamics](docs/agent-memory-survey/agent-memory-survey.md) | 基于 arXiv 2512.13564 综述沉淀，用 Forms（token-level / parametric / latent）、Functions（factual / experiential / working）、Dynamics（formation / evolution / retrieval）三棱镜统一碎片化的 agent memory 领域，辨析其与 LLM Memory / RAG / Context Engineering 的边界，梳理 benchmark 与开源框架、八个前沿方向，并给出形式选型、Evolution、Retrieval 静默失败防护与落地检查表。 |

## 学习路径

这个仓库会按 AI Agent 工程能力的成长路线持续补齐内容。当前已沉淀二十三份文档，后续新增文档后，会把对应节点回填到这张路线图中。

| 阶段 | 学习主题 | 需要掌握的问题 | 当前状态 |
|---:|---|---|---|
| 1 | 大模型基础原理 | Transformer Self-Attention、Decoder-Only、Tokenization、位置编码、KV Cache、LoRA/QLoRA、Embedding 选型等开发岗面试常考点的工程化梳理。 | 已沉淀：[Attention Is All You Need：Transformer 与纯注意力架构](docs/transformer/02-attention-is-all-you-need.md)、[Transformer Self-Attention：Q/K/V 与注意力怎么算](docs/transformer/01-transformer-self-attention.md)、[GPT vs BERT：为什么 LLM 都用 Decoder-Only](docs/gpt/01-decoder-only-vs-encoder-decoder.md)、[Tokenization：BPE / WordPiece / Unigram 怎么选](docs/tokenization/01-bpe-wordpiece-unigram.md)、[RoPE：旋转位置编码与相对注意力](docs/positional-encoding/01-rope-relative-position.md)、[推理采样参数：temperature / top_p / top_k](docs/sampling/01-temperature-top-p-top-k.md)、[KV Cache：自回归推理的工程加速](docs/kv-cache/01-kv-cache-inference.md)、[LoRA：低秩适配微调](docs/lora/01-lora-low-rank-adaptation.md)、[QLoRA：把 65B 微调压进单张 24GB 显卡](docs/qlora/01-qlora-quantized-lora.md)、[Embedding 模型选型：从 MTEB 排名到工程落地](docs/embedding/01-embedding-model-selection.md) |
| 1.x | 大模型基础代码路径 | 跟着 Karpathy "Zero to Hero" 视频系列从零手写 micrograd / makemore / nanoGPT / minbpe。 | 已沉淀：[Karpathy Zero to Hero：讲座列表与学习顺序](docs/zero-to-hero/01-karpathy-zero-to-hero-learning-path.md) |
| 2 | Agent 基础模型 | Agent loop 如何运转，模型、工具、状态和控制流如何配合。 | 已沉淀：[12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md)、[ReAct 框架：从推理行动循环到可控 Agent](docs/react-framework/react-framework.md) |
| 3 | Tool Calling 与工具系统 | Tool schema 如何设计，工具权限、失败、重试和审计如何处理。 | 已沉淀：[Tool Card 模板](docs/react-framework/tool-card-template.md)、[Writing Effective Tools for Agents：Agent 工具设计原则](docs/writing-tools-for-agents/writing-tools-for-agents.md) |
| 4 | Context Engineering | 什么信息应该进入上下文，如何压缩、隔离、检索和复用上下文。 | 已沉淀：[长文深度解析：大模型的上下文陷阱与 6 大修复技巧](docs/context-engineering/context-engineering.md)、[Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md)、[Agent 架构综述：从 Prompt 到上下文工程构建 AI Agent](docs/build-agent-context-engineering/build-agent-context-engineering.md) |
| 5 | Memory 与 RAG | 短期记忆、长期记忆、RAG、向量检索和知识库如何支撑 agent。 | 已沉淀：[Agent Memory 综述：Forms、Functions 与 Dynamics](docs/agent-memory-survey/agent-memory-survey.md) |
| 6 | Workflow 与 Multi-Agent | 什么时候用 workflow，什么时候拆 multi-agent，角色边界如何划分。 | 已沉淀：[Building Effective Agents：从简单模式到可控 Agent](docs/building-effective-agents/building-effective-agents.md)、[Loop Engineering：Karpathy Loop 与让它快 5 倍的双层循环](docs/loop-engineering/loop-engineering-karpathy-method.md) |
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
11. [Transformer Self-Attention：Q/K/V 与注意力怎么算](docs/transformer/01-transformer-self-attention.md)：回到大模型基础，从 Q/K/V 投影、Scaled Dot-Product 公式、Multi-Head、Masked、位置编码到 KV Cache 的工程含义，建立后续所有 LLM 主题的共同地基。
12. [GPT vs BERT：为什么 LLM 都用 Decoder-Only](docs/gpt/01-decoder-only-vs-encoder-decoder.md)：对比 Encoder-Only / Decoder-Only / Encoder-Decoder 三种拓扑，解释 BERT 的 MLM 与 GPT 的 Next Token Prediction 的本质分歧，并梳理 Decoder-Only 成为主流 LLM 事实标准的工程原因。
13. [Tokenization：BPE / WordPiece / Unigram 怎么选](docs/tokenization/01-bpe-wordpiece-unigram.md)：拆解子词切分的三种主流算法——BPE 自底向上合并、WordPiece 似然比合并、Unigram 自顶向下剪枝，掌握 SentencePiece 统一接口、tiktoken / rustbpe 工业实现、特殊 token 与词表大小对模型表现的权衡。
14. [RoPE：旋转位置编码与相对注意力](docs/positional-encoding/01-rope-relative-position.md)：理解当前主流 LLM 使用的位置编码机制——通过对 Q/K 按位置做旋转，使 attention 内积天然依赖相对位置 m-n，并掌握远程衰减、长度外推（PI / NTK-aware / YaRN）以及与 Flash Attention / KV Cache 的工程兼容点。
15. [推理采样参数：temperature / top_p / top_k](docs/sampling/01-temperature-top-p-top-k.md)：理解生成时的概率分布截断机制——Temperature 控锐度、Top-k 硬截断、Top-p Nucleus 自适应集合，并掌握 min_p / typical_p / contrastive、Repetition Penalty、Speculative Decoding 严格对齐等工程实践。
16. [KV Cache：自回归推理的工程加速](docs/kv-cache/01-kv-cache-inference.md)：从自回归推理逐步展开推导 KV Cache 的可复用性，掌握 QK^T 增量计算与显存估算、Prefill / Decode 两阶段、MHA / MQA / GQA 显存对比、PagedAttention（vLLM）分页与 prefix sharing、FlashAttention 兼容、Quantized KV Cache 与 Offload 等进阶优化。
17. [LoRA：低秩适配微调](docs/lora/01-lora-low-rank-adaptation.md)：理解全量微调的成本瓶颈与内在维度假设，掌握 W' = W + α/r · B·A 的低秩分解、target_modules / alpha / rank 工程选择、merge 推理，以及 AdaLoRA / DoRA 变体和 Hugging Face PEFT 工业框架。
18. [QLoRA：把 65B 微调压进单张 24GB 显卡](docs/qlora/01-qlora-quantized-lora.md)：理解 4-bit NormalFloat 量化基座 + Double Quantization 节省量化常数 + Paged Optimizers 顶住 OOM 尖峰 + 16-bit LoRA 训练的整体方案，掌握 65B 模型在单卡上的微调工程路径。
19. [Embedding 模型选型：从 MTEB 排名到工程落地](docs/embedding/01-embedding-model-selection.md)：建立 Embedding 模型的工程化认知，覆盖输入输出、Bi-Encoder vs Cross-Encoder、对称 vs 非对称检索、MTEB 8 类任务、闭源/开源模型分层、维度选择、Matryoshka 压缩、指令调优、中文场景、自家评测与 Sentence-Transformers / LangChain / LlamaIndex 工程集成。
20. [Karpathy Zero to Hero：讲座列表与学习顺序](docs/zero-to-hero/01-karpathy-zero-to-hero-learning-path.md)：整理 Karpathy "Neural Networks: Zero to Hero" 视频系列 8 讲的标题、时长、YouTube 链接、原文简介与配套代码仓库，按页面原样标注依赖关系。
21. [Loop Engineering：Karpathy Loop 与让它快 5 倍的双层循环](docs/loop-engineering/loop-engineering-karpathy-method.md)：理解 loop 与 prompt 的本质差别，掌握 verifier / state / stop condition 三要素、是否需要 loop 的四项检查、Karpathy AutoResearch 的三文件约束、automation / skill / sub-agents / connectors / verifier 五个构件，以及 Bilevel Autoresearch 在外层套 loop 实现 5 倍提升的架构原因。
22. [Attention Is All You Need：Transformer 与纯注意力架构](docs/transformer/02-attention-is-all-you-need.md)：回到 Transformer 原论文，理解用注意力取代 RNN/CNN 的动机、Scaled Dot-Product 缩放原理、Multi-Head 与三种注意力接线、Position-wise FFN、正余弦位置编码、复杂度对比、warmup 与 label smoothing 训练配方，以及与现代实现的工程检查清单。
23. [Agent Memory 综述：Forms、Functions 与 Dynamics](docs/agent-memory-survey/agent-memory-survey.md)：用 Forms（token-level / parametric / latent）、Functions（factual / experiential / working）、Dynamics（formation / evolution / retrieval）三棱镜统一碎片化的 agent memory 领域，辨析其与 LLM Memory / RAG / Context Engineering 的边界，并给出形式选型、Evolution 三机制、Retrieval 静默失败防护与落地检查表。

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
│   ├── build-agent-context-engineering/
│   │   ├── build-agent-context-engineering.md
│   │   └── images/
│   ├── transformer/
│   │   ├── 01-transformer-self-attention.md
│   │   ├── 02-attention-is-all-you-need.md
│   │   └── figures/
│   ├── gpt/
│   │   ├── 01-decoder-only-vs-encoder-decoder.md
│   │   └── figures/
│   ├── tokenization/
│   │   ├── 01-bpe-wordpiece-unigram.md
│   │   └── figures/
│   ├── positional-encoding/
│   │   ├── 01-rope-relative-position.md
│   │   └── figures/
│   ├── sampling/
│   │   ├── 01-temperature-top-p-top-k.md
│   │   └── figures/
│   ├── kv-cache/
│   │   ├── 01-kv-cache-inference.md
│   │   └── figures/
│   ├── lora/
│   │   ├── 01-lora-low-rank-adaptation.md
│   │   └── figures/
│   ├── qlora/
│   │   ├── 01-qlora-quantized-lora.md
│   │   └── figures/
│   └── embedding/
│       ├── 01-embedding-model-selection.md
│       └── figures/
│   ├── zero-to-hero/
│   │   ├── 01-karpathy-zero-to-hero-learning-path.md
│   │   └── figures/
│   └── loop-engineering/
│       ├── loop-engineering-karpathy-method.md
│       └── figures/
```

## 后续计划

- 本轮 9 个 LLM 基础主题已全部沉淀，Q9（RLHF / DPO）、Q10（量化）、Q11（推理服务框架）按用户节奏延后启动。
- Memory 综述已沉淀（Forms / Functions / Dynamics 三棱镜），后续继续补充 RAG、向量检索与知识库专题，以及更细的 Multi-Agent 工程案例。
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
