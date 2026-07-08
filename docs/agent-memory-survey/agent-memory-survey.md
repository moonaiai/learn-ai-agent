# Agent Memory 综述：Forms、Functions 与 Dynamics

> 论文链接：https://arxiv.org/abs/2512.13564

## 核心结论

《Memory in the Age of AI Agents: A Survey》把 agent memory 从一个被滥用的热词，重新框定为一等（first-class）的设计原语。论文的核心主张是：memory 不是辅助存储，而是 agent 实现**时间连贯性、持续适应、长程能力**的底层支撑；静态 LLM 之所以能转变为持续与环境交互、自我改进的 agent，关键就在 memory。

论文用统一的三棱镜重新组织了这个碎片化的领域：

- **Forms（形式）**：记忆以什么承载——`token-level`、`parametric`、`latent`。
- **Functions（功能）**：为什么需要记忆——`factual`、`experiential`、`working`，取代过去粗粒度的 long/short-term 二分。
- **Dynamics（动态）**：记忆如何运作与演化——`formation`、`evolution`、`retrieval` 三个生命周期算子。

![图 1：Agent Memory 的 Forms-Functions-Dynamics 统一分类](figures/overview-forms-functions-dynamics.png)

这张总览图把记忆按形式（横轴）与功能（纵轴）定位，并把代表性系统映射进同一坐标系，给出一个可对照的全景。对工程读者的直接价值是：选型时不再只问"要不要加 memory"，而是同时回答"用什么形式承载、为什么功能服务、按什么节奏形成/演化/检索"。

## 名词解释

| 名词 | 解释 | 简单例子 |
|---|---|---|
| Agent Memory | agent 在与用户/环境交互中持续形成、演化、检索的记忆状态，跨任务持久且自演化 | 代码 agent 记住"这个项目用 pnpm 不用 npm"，下次直接用对 |
| Token-level Memory | 以持久、离散、外部可访问可编辑的单元存储，显式 retrieval | 把用户偏好写成一条条 memo 存进向量库 |
| Parametric Memory | 把信息编码进模型参数（权重或 adapter），forward 时隐式召回 | 用 LoRA 把领域知识微调进模型 |
| Latent Memory | 隐式携带在模型内部表示（KV cache、hidden states、latent embeddings）中的记忆 | 复用上一轮的 KV cache 避免重算 |
| Factual Memory | 关于用户、环境、外部世界的 declarative 事实，保证一致性 | 记住"用户对花生过敏" |
| Experiential Memory | 跨 episode 累积的过程性/策略性经验，支撑持续学习 | 把成功修 bug 的步骤沉淀成可复用 workflow |
| Working Memory | 单任务内对 context 的主动管理，容量受限的 scratchpad | 长研究中把已完成子任务折叠成摘要 |
| Memory Formation | 把原始交互产物选择性提炼为记忆候选的算子 $F$ | 把一轮对话蒸馏成"用户目标 + 已确认约束" |
| Memory Evolution | 把新记忆整合进已有库（合并、消解冲突、遗忘）的算子 $E$ | 新事实"用户已搬家"覆盖旧地址 |
| Memory Retrieval | 在决策时按当前任务构造 query 取回相关记忆的算子 $R$ | 回答前先检索与当前问题相关的历史偏好 |
| inside-trial / cross-trial | 短期/长期不是独立模块，而是 formation/evolution/retrieval 的调用频率涌现的结果 | 每步都检索=短期；任务边界才更新=长期 |
| Stability–Plasticity 困境 | 更新记忆时何时覆写旧知识、何时把新信息当噪声的核心矛盾 | 改了一条事实却顺带忘了相关旧知识 |
| Agentic RAG | 把检索嵌入自主决策循环，agent 主动控制检索时机与方式的 RAG 变体 | agent 自己判断"信息不够"再触发检索 |

## 1. 为什么需要新的 Agent Memory 分类法

过去两年 LLM 演进为 agent，被普遍拆解为 reasoning / planning / perception / memory / tool-use 等能力。其中 reasoning、tool-use 已大量通过 RL 内化进模型参数，而 memory 仍严重依赖外部 agentic scaffolds。论文认为 memory 是把"参数无法快速更新的静态 LLM"转化为"可通过环境交互持续适应的 agent"的基石。

论文提出新分类法的双重动机：

1. **既有分类法已过时**：早期 survey 的分类体系形成于近期方法论突破之前，无法反映当前广度。例如 2025 年新方向——从历史经验蒸馏可复用工具（AgentDistill、ALITA、PyVision）、memory-augmented test-time scaling（Latent Evolve、Dynamic Cheatsheet）——在旧分类里没有位置。
2. **概念碎片化**：声称研究 "agent memory" 的论文在实现、目标、假设上差异巨大；术语泛滥（declarative / episodic / semantic / parametric memory…）进一步模糊边界。传统的 long/short-term 二分不足以刻画当代 agent memory 的多样性与动态性。

工程含义：当团队说"给 agent 加 memory"时，必须先对齐到同一套分类，否则 token-level 的工程师和 parametric 的研究员在谈完全不同的东西。

## 2. 形式化定义：Agent、Memory 与生命周期算子

论文给出一组形式化定义，把 agent memory 从模糊概念变成可讨论的工程对象。

### 2.1 LLM-based Agent 系统

- 环境 $\mathcal{S}$ 按受控随机转移演化：$s_{t+1} \sim \Psi(s_{t+1} \mid s_t, a_t)$。
- agent $i$ 的观测：$o_t^i = O_i(s_t, h_t^i, \mathcal{Q})$，其中 $h_t^i$ 是可见交互历史，$\mathcal{Q}$ 是任务规格（用户指令/目标/约束，单任务内固定）。
- action space 异构且语义结构化：自然语言生成、tool invocation、planning、environment-control、communication。所有动作由 autoregressive LLM 在上下文条件下产生。
- policy：$a_t = \pi_i(o_t^i, m_t^i, \mathcal{Q})$，其中 $m_t^i$ 是 memory-derived signal。

### 2.2 Agent Memory 系统与三个算子

统一的 memory state $\mathcal{M}_t \in \mathbb{M}$，不预设内部结构（text buffer / KV store / vector DB / graph / 混合皆可）。其动态由三个算子刻画：

| 算子 | 形式 | 作用 |
|---|---|---|
| Formation $F$ | $\mathcal{M}_{t+1}^{\mathrm{form}} = F(\mathcal{M}_t, \phi_t)$ | 把 artifacts $\phi_t$（工具输出、推理 trace、反馈）选择性转化为记忆候选，而非逐字存全部历史 |
| Evolution $E$ | $\mathcal{M}_{t+1} = E(\mathcal{M}_{t+1}^{\mathrm{form}})$ | 整合进已有库：合并冗余、消解冲突、丢弃低效用、重构以利检索 |
| Retrieval $R$ | $m_t^i = R(\mathcal{M}_t, o_t^i, \mathcal{Q})$ | 构造 task-aware query 取回相关记忆，格式化为 policy 可消费的形式 |

### 2.3 关键论点：短期/长期是涌现，不是模块

三个算子不必每步调用。有的系统只在任务初始化检索一次（$t>0$ 时 $m_t^i = \bot$），有的持续检索；formation 可以是最小化的原始观测累积，也可以是复杂 pattern 抽取。论文的核心论点是：

> **inside-trial（短期）与 cross-trial（长期）memory 不是离散的架构模块，而是从 formation / evolution / retrieval 的时间调用模式中涌现的现象。**

工程含义：不要一上来就建"短期记忆模块 + 长期记忆模块"，而是先决定三个算子的调用频率与触发条件——同一个 memory container 通过不同的调用节奏就能同时承担短期与长期角色。

## 3. 概念辨析：Agent Memory 与 LLM Memory / RAG / Context Engineering

这是论文最具澄清价值的部分。社区常把 agent memory 与 LLM memory、RAG、context engineering 混为一谈，论文用一张 Venn 图给出边界。

![图 2：Agent Memory 与 LLM Memory / RAG / Context Engineering 的概念关系](figures/concept.png)

### 3.1 Agent Memory vs LLM Memory

- 2023 年起许多自称 "LLM memory" 的工作（MemoryBank、MemGPT）在现代术语下实为 agent memory 的早期实例——它们解决的本来就是 agentic 挑战（跟踪用户偏好、dialogue state、跨轮累积经验）。
- **真正不属于 agent memory 的 LLM-internal memory**：管理 KV cache、设计 long-context 处理机制、改模型架构（RWKV、Mamba、diffusion-based LMs）。这些聚焦模型内在动力学，目标是扩展表征容量，不支持跨任务持久化与环境驱动适应。
- 判据：直接干预模型内部状态（架构修改、cache rewriting、recurrent-state persistence）属 LLM memory；围绕 agent 与环境持续交互、有 formation/evolution/retrieval 的 deliberate 操作属 agent memory。

### 3.2 Agent Memory vs RAG

经典 RAG 增强 LLM 访问**静态外部知识源**，为 grounding、降幻觉，但不维护内部演化的交互记忆。Agent memory 内生于 agent 与环境的**持续交互**，不断把自身动作与环境反馈纳入持久库。三种 RAG 谱系与 agent memory 的关系：

| RAG 谱系 | 特征 | 与 agent memory 的关系 |
|---|---|---|
| Modular RAG | 检索分 indexing/retrieval/rerank/filter/assembly 的静态流水线 | 对应 agent memory 的 retrieval 阶段（Memary、MemOS、Mem0） |
| Graph RAG | 知识库组织为图，图遍历/图排序支持多跳推理 | 两边都用图检索，但只有 agent memory 把图视为 living、evolving 的经验表示（Mem0$^g$、A-MEM、Zep、G-Memory） |
| Agentic RAG | 检索嵌入自主决策循环，agent 控制 when/how/what | 概念空间最近；区别在 agentic RAG 操作**外部** task-specific 库，agent memory 维护**内部、持久、自演化**的库 |

### 3.3 Agent Memory vs Context Engineering

Context engineering 是系统化设计方法论，把 context window 当受约束的计算资源来调度，属 **resource management** 范式；agent memory 属 **cognitive modeling** 范式（持久实体 + evolving identity）。两者在长程交互的 working memory 技术实现上高度收敛（压缩、组织、选择），但范围不同：前者构建外部 scaffolding 与接口正确性，后者管理 agent 知道什么、经历过什么、这些如何随时间演化。

### 3.4 一张表理清四个概念

| 维度 | Agent Memory | LLM Memory | RAG | Context Engineering |
|---|---|---|---|---|
| 核心定位 | 持久、自演化的认知状态 | 模型内在表征容量扩展 | 静态外部知识源按需检索 | context window 作为受约束资源的调度 |
| 时间特性 | 跨任务持久、持续演化 | 序列内/架构内 | 多为单次推理任务 | 瞬态/单次推理的信息组织 |
| 范式 | cognitive modeling | 架构优化 | 知识访问 | resource management |
| 典型机制 | F/E/R 算子、vector/graph/parametric/latent store | KV cache、RWKV/Mamba、attention sparsity | modular/graph/agentic RAG | token pruning、rolling summary、MCP |
| 演化性 | 内部、持久、自演化 | 模型内部状态重组 | 外部库（agentic RAG 例外） | 不演化（接口/调度层） |

## 4. Forms：记忆以什么承载

论文按"记忆存储在哪、以何种形式表示"分为三大类。三者没有单一最优，而是面向不同任务场景的不同结构性能力。

### 4.1 Token-level Memory

定义为持久、离散、外部可访问可检视的单元。这里的 "token" 是广义概念——不止文本 token，还包括 visual tokens、audio frames，任何可在模型参数之外被写入、retrieved、重组、修订的离散元素。因显式，故透明、易编辑、易解释，是 retrieval、routing、conflict handling 的天然层，也是现有工作量最大的形式。

按单元间结构拓扑复杂度分三子类：

![图 3：Token-level Memory 的 1D/2D/3D 拓扑分类](figures/sec3-3.1.png)

| 子类 | 拓扑 | 代表系统 | 特点 |
|---|---|---|---|
| Flat Memory (1D) | 无显式单元间拓扑 | MemGPT、Mem0、Reflexion、Voyager、MemoryBank | 序列或单元袋累积，append/prune 成本低，但 coherence 依赖 retrieval 质量，易冗余噪声 |
| Planar Memory (2D) | 单层 graph/tree/table | Ret-LLM、HAT、A-MEM、COMET、Optimus-1 | 从"存储"跃迁到"组织"，支持结构化查找与关系遍历，但无分层、构建搜索成本高 |
| Hierarchical Memory (3D) | 跨多层带层间链接 | GraphRAG、Zep、HippoRAG、HiAgent、G-Memory | 支持多抽象度与多路径检索，任务表现强，但结构复杂、最优布局仍是难题 |

Flat Memory 内部又按设计目标分 Dialogue / Preference / Profile / Experience / Multimodal 五组。一个清晰演进线索：从存原始对话历史（SCM、RecursiveSum）→ OS 隐喻分层管理（MemGPT）→ 多粒度认知对齐（SemanticAnchor、EM-LLM 的 Bayesian surprise 分段）→ 自适应优化（Mem0 标准化维护操作、Memory-R1 引入 RL 优化 memory 构建）。

工程权衡：Flat 适合广覆盖与轻量更新，不适合结构化推理；Planar/Hierarchical 检索精度高但构建维护成本高。选型取决于任务是否需要多跳推理与稳定知识组织。

### 4.2 Parametric Memory

把信息直接存入模型参数，让模型内化并召回而无需外部存储。分两子类：

| 子类 | 含义 | 注入时机 | 代表方法 | 工程权衡 |
|---|---|---|---|---|
| Internal Parametric Memory | 编码进模型原始权重 | pre/mid/post-train | LMLM、CharacterGLM、ROME/MEMIT、CoLoR | 结构简单无额外推理开销，但更新需重训、易灾难性遗忘 |
| External Parametric Memory | 存于 adapter/LoRA/辅助模型，不改原始权重 | SFT/FT | K-Adapter、WISE、ELDER、MemLoRA | 模块化可增删换、避免全局遗忘，但注入效果取决于与内部知识的接口 |

设计选择本质是：memory 完全吸收进基座，还是模块化附加在旁。Internal 适合大规模领域知识/任务先验；External 适合需要模块化更新、任务个性化、可控回滚的场景；两者都不适合个性化 memory 短片段或 working memory。

### 4.3 Latent Memory

隐式携带在模型内部表示（KV cache、activations、hidden states、latent embeddings）中的记忆，不以明文暴露。推理延迟更低，可能带来更好性能，但可解释性差。按 latent state 来源分三种模式：

![图 4：Latent Memory 的 Generate / Reuse / Transform 三模式](figures/latent.png)

| 模式 | 机制 | 代表方法 | 工程权衡 |
|---|---|---|---|
| Generate | 由独立模型/模块产生新 latent 表示作为可复用 memory 单元 | Gist、AutoCompressor、MemoRAG、MemoryLLM、Titans、MemGen | 高信息密度、支持跨 episode；但生成有信息损失/偏差，多次读写可能漂移 |
| Reuse | 直接复用先前计算的 activations（主要是 KV cache），不变换 | Memorizing Transformers、FOT、LONGMEM | 完整 fidelity、概念简单；但 KV 随 context 快速增长，内存大、检索效率降 |
| Transform | 修改/压缩/重构现有 latent states | SnapKV、PyramidKV、H2O、SirLLM、R³Mem | 紧凑高效检索；但有信息损失风险，压缩后更难解释验证 |

注意：Generate 与 parametric memory 易混淆。论文的判据是**按记忆形式而非学习机制分类**——虽经学习编码生成，但产出的 latent 表示被显式实例化并作为独立 memory 单元复用，就归 Generate latent memory，而非 parametric。

### 4.4 三种形式的适配与取舍

![图 5：Token-level / Parametric / Latent 三种 memory 范式对比](figures/comparison.png)

论文强调：memory 类型选择反映设计者期望信息如何塑造 agent 行为，不只是"记住什么"。三者按表示形式、更新动态、可解释性、效率形成互补：

| 维度 | Token-level | Parametric (Internal) | Parametric (External) | Latent (Generate) | Latent (Reuse) | Latent (Transform) |
|---|---|---|---|---|---|---|
| 透明度 | 高（可检视可编辑） | 低 | 中（模块化可替换） | 低 | 低 | 低（压缩后更难） |
| 更新难度 | 低（append/prune） | 高（需重训） | 中（增删 adapter） | 中 | 中（索引策略） | 中 |
| 容量 | 可扩展但易冗余噪声 | 受参数量限 | 受 adapter 数限 | 紧凑高密度 | KV 随 context 增长 | 紧凑（有损） |
| 遗忘 | 无灾难性遗忘 | 易遗忘旧 memory | 避免全局遗忘 | 多次读写可能漂移 | 无损 | 有损失风险 |
| 典型场景 | 对话/个性化/推荐/合规 | 领域知识/任务先验 | 模块化更新/个性化 | 长上下文压缩/多模态 | 长程检索 | 长上下文高效推理 |

适配原则：需要显式推理、可控性、可问责性、高频更新或可验证 provenance 的场景选 token-level；需要概念理解与广泛模式归纳、可内化为分布表示的场景选 parametric；优先性能与可扩展性而非可解释性、多模态或端侧部署选 latent。

## 5. Functions：为什么需要记忆

论文从"为什么"切入，主张 agent memory 不是单一组件而是一组功能能力，并用更细粒度的 taxonomy 取代 long/short-term 二分。

![图 6：Agent Memory 的功能分类——三大支柱与两个时间域](figures/sec4-all-new.png)

三大功能支柱构成一个认知回路：交互产物经 encoding 固化进 long-term memory，在 working memory 内即时处理，再从 factual/experiential memory 取回 context 与 skill 填充 workspace。

### 5.1 Factual Memory

存储关于用户、环境、外部世界的显式 declarative 事实，使 agent 能用历史信息解读当前输入。理论基础是 declarative memory（episodic + semantic），但在 agent 中二者是连续谱：原始事件流经 summarization / reflection / entity extraction / fact induction 转为可复用 semantic fact base。三大功能属性：consistency（跨时间稳定）、coherence（上下文感知）、adaptability（个性化对齐）。

| 子类 | 指向实体 | 典型事实 | 代表系统 |
|---|---|---|---|
| User factual memory | 用户 | 身份、稳定偏好、任务约束、历史承诺 | MemoryBank、Mem0、TiM、RMM、MemGuide |
| Environment factual memory | 外部世界 | 文档状态、资源可用性、其他 agent 能力 | HippoRAG、MemTree、LMLM、Zep、AriGraph |

User factual memory 的工程四要素是 selection & compression / structured organization / retrieval & reuse / consistency governance，在有限访问成本下维持长程对话连贯。Environment factual memory 还要解决多 agent 共享访问的去重与一致性治理。

### 5.2 Experiential Memory

将历史 trajectory、蒸馏策略、交互结果编码为持久可检索表示，对应人类 procedural memory，是 continual learning 与 self-evolution 的基础。关键战略意义：提供**非参数化适应路径**，避免频繁参数更新的高昂成本。

![图 7：Experiential Memory 按抽象层级分类](figures/sec4-4.2.png)

| 子类 | 抽象层级 | 形式 | 代表系统 |
|---|---|---|---|
| Case-based Memory | 最低，原始记录 | Solution / Trajectory | ExpeL、Memento、JARVIS-1、MemRL |
| Strategy-based Memory | 中，蒸馏可迁移 pattern | Insight / Workflow / Pattern | Reflexion、AWM、Buffer of Thoughts、H²R、R2D2 |
| Skill-based Memory | 最高，可执行 | API / Function / Code Snippet / MCP | Voyager、Gorilla、CREATOR、Alita、ToolMem |
| Hybrid Memory | 多形式集成 | 跨格式动态选择 | ExpeL、Agent KB、ChemAgent、LARP |

三层递进：case 高保真但检索噪声大；strategy 可泛化但只是结构指南、不直接与环境交互；skill 可调用可验证可组合，是 perception–reasoning–action loop 的锚点。robust agent 通常 strategy 提供抽象规划 + skill 落地执行。skill 的统一判定准则是 callable / verifiable / composable，演进方向是从静态 code snippet → 模块化 script → 标准化 API → MCP → 可学习架构。

### 5.3 Working Memory

单 episode 内对 context 的主动管理，目标是把 context window 从被动只读 buffer 变成可控、可更新、抗干扰的 workspace。理论基础是认知科学的 working memory（容量受限、动态控制），强调资源约束下的主动控制而非临时存储。当前模型行为证据表明不具备类人 working memory，需显式工程化。

| 子类 | 关注点 | 机制 | 代表系统 |
|---|---|---|---|
| Single-turn Working Memory | 输入凝缩与抽象 | input condensation（hard/soft/hybrid）+ observation abstraction | LLMLingua、Gist、AutoCompressors、VideoAgent |
| Multi-turn Working Memory | 时序状态维持 | state consolidation + hierarchical folding + cognitive planning | Mem1、MemAgent、ReSum、HiAgent、Context-Folding、PRIME |

Multi-turn 的三类机制协同：state consolidation 把增长 trajectory 映射到固定大小状态空间；hierarchical folding 按 subgoal 分解、子任务完成后折叠为摘要；cognitive planning 维持外化的 plan 或 world model 指导未来动作。核心效果是把推理性能与交互长度解耦——在严格计算/内存约束下跨无限 horizon 维持时序连贯与目标对齐。

### 5.4 三大支柱的跨功能权衡

| 维度 | Factual | Experiential | Working |
|---|---|---|---|
| 时间域 | Long-term | Long-term（跨 episode） | Short-term（单 episode） |
| 抽象粒度 | 原始事件→摘要→reflection→semantic fact | case→strategy→skill | token→latent→结构化 state/plan |
| 噪声抑制 | 去重 + 一致性检查 + 压缩 | 蒸馏抽象去 context-dependent 噪声 | hard/soft 压缩 + folding |
| 失败模式 | 共指漂移 / 重复询问 / 矛盾 | case 检索噪声 / strategy 不直接交互 | context 窒息 / goal drift / latency |
| 优化范式 | PE 为主，少量 SFT/RL | PE/SFT/RL 混合，RL 在 trajectory 类突出 | RL 突出（多轮 state 类） |

## 6. Dynamics：记忆如何运作与演化

静态视图（架构形式 + 功能角色）忽略记忆的动态性。论文把完整生命周期解耦为三个相互耦合的过程，形成闭环：Formation 产物 → Evolution 整合 → Retrieval 调用 → 推理结果与环境反馈回流到 Formation/Evolution。

![图 8：记忆操作的 Dynamics 全景——Formation / Evolution / Retrieval](figures/sec5-whole.png)

### 6.1 Memory Formation

把原始上下文（dialogues、images、trajectories）编码为紧凑知识。必要性来自原始上下文长、噪声大、高度冗余，导致 full-context prompting 的计算开销与 OOD 长度下推理退化。Formation 把本质信息蒸馏为可高效存储、精准检索的表示。按信息压缩粒度与编码逻辑分五类：

| 类别 | 核心思想 | 输出形式 | 代表方法 |
|---|---|---|---|
| Semantic Summarization | 长数据→紧凑摘要，保全局高层语义 | 文本/多模态摘要 | MemGPT、Mem0、Mem1（RL 优化）、MemoryBank |
| Knowledge Distillation | 提取特定认知资产（事实到策略） | 事实/经验 insight | TiM、AWM、ExpeL、R2D2、Memory-R1 |
| Structured Construction | 无结构数据→显式拓扑（图/树） | 图/树/层次结构 | KGT、GraphRAG、Zep、RAPTOR、A-MEM |
| Latent Representation | 原始经验直接编码为向量/KV state | latent embedding | MemoryLLM、M+、MemGen、CoMEM |
| Parametric Internalization | 外部记忆固化进模型权重 | model parameters | MEND、ROME、MEMIT、CoLoR、ToolFormer |

五类非互斥，单一算法可融合多种。各有损/无损取向：Summarization 牺牲局部精度换上下文压缩；Latent 牺牲可解释性换密度；Parametric 牺牲灵活性换零延迟。Knowledge Distillation 是更复杂 formation 的基础组件——每条知识是扁平单元，直接存入无结构表会忽略关系，故需 Structured Construction。

### 6.2 Memory Evolution

Formation 提取后需与已有库整合。朴素 append 忽略语义依赖、潜在矛盾与时序有效性。Evolution 通过 consolidation / conflict resolution / pruning 保证长期知识的紧凑性、一致性、相关性。

![图 9：Memory Evolution 的三类机制——Consolidation / Updating / Forgetting](figures/sec5-mem-evolution.png)

| 机制 | 目标 | 代表方法 | 核心矛盾 |
|---|---|---|---|
| Consolidation | 短期痕迹→结构化可泛化长期知识 | RMM（local）、PREMem（cluster）、Matrix（global） | 信息平滑风险——异常事件/独特例外丢失 |
| Updating | 解决新旧冲突，维持事实一致性 | Zep（时序软删除）、MOOM/LightMem（双阶段延迟一致性）、Mem-$\alpha$（学习式策略）、ROME（model editing） | stability–plasticity 困境 |
| Forgetting | 释放容量、聚焦显著知识 | MemGPT（时间）、XMem/MemOS（频次 LRU）、MemoryBank/TiM（重要性） | LRU 等启发式可能消除长尾必需知识 |

Updating 的演进线索很有工程价值：规则式硬替换（MemGPT，破坏时序）→ 时序感知软删除（Zep，标注 invalid timestamp 而非删除）→ 双阶段延迟一致性（MOOM/LightMem，在线软更新+离线反思巩固）→ 学习式策略（Mem-$\alpha$，把更新建模为 policy-learning）。Forgetting 三类对应创建时间、检索活跃度、综合语义估值，趋势是从静态数值打分走向语义智能的"有意识遗忘"。

### 6.3 Memory Retrieval

在恰当时刻从记忆库检索相关且简洁的片段支持当前推理。基于检索执行顺序分四阶段：when/where → what → how → how to integrate。

| 阶段 | 关注点 | 代表方法 |
|---|---|---|
| Retrieval Timing and Intent | 何时触发、查哪个库 | MIRIX（always-on）、MemGPT/MemTool（LLM 自主触发）、MemOS（动态选源）、MemGen（latent 触发） |
| Query Construction | 缩小原始 query 与记忆索引的语义 gap | HyDE（假设文档）、Visconde（分解）、MemoRAG（压缩记忆+草稿改写） |
| Retrieval Strategies | 执行搜索 | BM25（词法）、Sentence-BERT/CLIP（语义）、HippoRAG/AriGraph（图遍历+PageRank）、混合检索 |
| Post-Retrieval Processing | re-rank / filter / aggregate | Zep（时序过滤）、Memento（Q-learning 重排）、ComoRAG（聚合压缩） |

自主时机与意图能减少计算开销与噪声，但脆弱点是"静默失败"——agent 高估自身知识而未触发检索，知识缺口导致幻觉。近期研究重心从设计复杂记忆架构转向检索构造过程，记忆角色转向"服务于检索"。

## 7. 资源：Benchmark 与开源框架

### 7.1 Benchmark（两大类）

| 类别 | 关注点 | 代表 |
|---|---|---|
| 面向 memory / lifelong / self-evolving agents | retention/retrieval、catastrophic forgetting、forward/backward transfer、self-reflection | LoCoMo、LongMemEval、MemBench、PersonaMem、PrefEval、StreamBench、MemoryAgentBench、LOCCO |
| 隐式压测长程记忆的相关 benchmark | 长程 episode 内状态保持、多步导航、跨任务知识保留 | SWE-Bench Verified、GAIA、WebArena、ALFWorld、AgentGym |

选型含义：评估对话级用户记忆一致性用 LoCoMo/LongMemEval；评估长程任务状态保持用 StreamBench/SWE-Bench；评估自演化用 MemoryAgentBench。

### 7.2 开源 Memory 框架

按定位从 agent-centric（丰富分层抽象）到 general-purpose retrieval/memory-as-a-service backend 的谱系：

| 类别 | 代表框架 | 一句话 |
|---|---|---|
| 分层 S/LTM | MemGPT、MemoryOS | 分层 short/long-term store，丰富认知抽象 |
| 图 + 向量 / 时序 KG | Mem0、Mem0$^g$、Zep、Cognee | 图结构记忆，支持关系推理与时序 |
| 结构化画像 | Memobase、MIRIX | 用户画像或结构化记忆条目 |
| 树形记忆 + memcube | MemOS | 树形记忆 + memcube 抽象 |
| 通用向量/图数据库后端 | Pinecone、Chroma、Weaviate | 通用检索后端 |
| 多模态 / 模块化空间 | SuperMemory、MemU、MemEngine | 多模态或模块化记忆空间 |

多数框架显式分离 short/long-term store，越来越多支持 experiential traces，multimodal 较新。部分已在 LoCoMo、LongMemEval、MemoryAgentBench 等基准上报结果。

## 8. 前沿方向

论文给出八个 frontier 的 look-back + future perspective，对工程选型有前瞻指引。

![图 10：RL 与 Agent Memory 结合的演化路线](figures/frontier-rl-memory-new.png)

| 前沿 | Look Back | Future |
|---|---|---|
| Retrieval vs Generation | 主流是 memory retrieval；近期转向 memory generation（retrieve-then-generate 与 direct generation） | 生成式 memory 应 context adaptive、跨异构信号整合、可学习自优化 |
| Automated Memory Management | 现有系统依赖手工策略（Mem0 固定指令、A-MEM 人工规则） | 通过显式 tool calls 把 construction/evolution/retrieval 集成进决策循环；self-optimizing memory structures |
| RL Meets Memory | 从 RL-free（启发式 pipeline）→ RL-assisted（RL 管辖选定组件） | fully RL-driven：最小化人造先验、agent 全阶段控制，memory 成协同进化的可学习子系统 |
| Multimodal Memory | 文本趋于成熟，视觉/视频受关注，音频欠探索 | 当前无真正 omnimodal support；需灵活容纳多模态、保持语义对齐与时序连贯 |
| Shared Memory in MAS | 从 isolated local + message passing → centralized shared memory | 走向 agent-aware（读写按角色/信任）、learning-driven 管理 |
| Memory for World Model | Frame Sampling / Sliding Window → SSM / Explicit Memory Banks / Sparse Retrieval | 从 Data Caching 走向 State Simulation；Dual-System（快 SSM + 慢 VLM）+ Active Memory Management |
| Trustworthy Memory | 从 RAG 的 hallucination 关注演化到 memory 的更广 trust 议题 | 三支柱：privacy preservation、explainability、hallucination robustness；长期愿景是 OS 式抽象 |
| Human-Cognitive Connections | 架构趋同 Atkinson-Shiffrin / Tulving 模型，但 dynamics 分歧——人脑是 constructive，agent 依赖 verbatim retrieval | 引入 offline consolidation（类睡眠）与 generative reconstruction，解决 stability-plasticity |

其中 RL 与 memory 的三阶段演化对工程路线影响最大：当前主流仍是 RL-free 的启发式 pipeline（简单实用、可解释、可控，将长期存在），RL-assisted 已在 working memory 管理（Context Folding、MemSearcher、IterResearch）落地，fully RL-driven 是下一阶段——让 agent 通过 RL 优化动力学自发涌现新 memory 组织/格式/schema/update rule，摆脱 cortical/hippocampal 类比与预定义 episodic/semantic/core 分类。

## 9. 工程启发与落地检查

把论文的 taxonomy 翻译成工程决策，可以归纳为几条主线：

1. **先对齐分类再选型**。团队讨论"加 memory"前，先用 Forms/Functions/Dynamics 三棱镜对齐：用什么形式承载、为什么功能服务、三个算子按什么节奏调用。避免 token-level 工程师与 parametric 研究员各说各话。
2. **短期/长期是调用模式不是模块**。不要一上来就建两个独立模块，先用同一个 memory container + 不同调用频率承担双角色，再按需拆分。
3. **形式选型跟着任务可问责性走**。需要可审计 provenance、精确增删改、高频更新选 token-level；需要概念泛化与零延迟选 parametric；优先性能与多模态选 latent。
4. **Evolution 不是可选优化**。朴素 append 会在长程交互中积累冗余与矛盾。至少要设计 consolidation（去冗余）、updating（消解冲突）、forgetting（释放容量）三件事的触发条件。
5. **警惕 Retrieval 的静默失败**。自主时机/意图能省成本，但 agent 高估自身知识会不触发检索而幻觉。要有兜底：关键决策强制检索、低置信 abstention、fallback to priors。
6. **Updating 优先走延迟一致性**。在线硬替换破坏时序；学习式策略是前沿。生产可先用双阶段（在线软更新 + 离线反思巩固）平衡延迟与连贯。
7. **Forgetting 要保护长尾**。纯 LRU/频次会消除少访问但必需的知识。当存储成本非关键约束时，避免直接删除，改用权重衰减（软遗忘）。
8. **Experiential memory 按 case→strategy→skill 分层沉淀**。robust agent 通常 strategy 提供规划 + skill 落地执行。skill 必须满足 callable / verifiable / composable，并优先向 MCP 等标准接口收敛。
9. **Trustworthy 是一等约束不是后置**。memory 常存 user-specific、持久、潜在敏感内容，需 access control、verifiable forgetting、auditable updates；shared/federated memory 引入集体隐私。

落地检查表：

| 维度 | 检查项 | 期望状态 |
|---|---|---|
| 分类对齐 | Forms/Functions/Dynamics 三维是否都有明确选择 | 三维均有明确答案且互相自洽 |
| 算子设计 | formation/evolution/retrieval 的触发频率与条件是否定义 | 三算子调用模式显式定义，短期/长期从模式涌现 |
| 形式选型 | 是否按可问责性/更新频率/性能需求选 form | 选型理由可追溯到任务约束 |
| Evolution | consolidation/updating/forgetting 是否都有机制 | 三机制均有触发条件与实现 |
| Retrieval 兜底 | 是否有静默失败防护 | 关键决策强制检索或低置信 abstention |
| Updating 策略 | 是否避免破坏性硬替换 | 时序感知软删除或双阶段延迟一致性 |
| Forgetting 长尾 | 是否保护少访问但必需知识 | 软遗忘或重要性驱动，非纯 LRU |
| 经验沉淀 | experiential memory 是否分层 | case/strategy/skill 至少两层，skill 可调用可验证 |
| 评测 | 是否在对应 benchmark 验证 | 用 LoCoMo/LongMemEval/StreamBench 等对口基准 |
| 信任 | 隐私/可解释/鲁棒是否落地 | access control + verifiable forgetting + auditable updates |

## 10. 关键结论

- **Memory 是一等原语**。它不是辅助存储，而是 agent 实现时间连贯、持续适应、长程能力的底层支撑；静态 LLM 转变为持续交互、自我改进的 agent，关键在 memory。
- **Forms–Functions–Dynamics 三棱镜**统一了一个碎片化领域。Forms 回答"以什么承载"（token-level/parametric/latent），Functions 回答"为什么服务"（factual/experiential/working），Dynamics 回答"如何运作"（formation/evolution/retrieval）。
- **短期/长期是涌现**。它们不是离散架构模块，而是三个算子时间调用模式的结果——同一容器、不同节奏即可同时承担短期与长期。
- **从 retrieval 走向 generation、从手工走向 RL-driven**。memory 系统正变得 fully learnable、adaptive、self-organizing，把 LLM 从静态生成器转变为能持续交互、self-improvement、随时间 principled reasoning 的 agent。
- **工程启示**：选型前先对齐分类；Evolution 不是可选；Retrieval 要防静默失败；Trustworthy 是一等约束。Memory 设计是 robust、general、enduring AI 的决定性开放问题。
