# AI Agent 安全工程与对抗性防御：深度调研报告

> **AI Engineering 系列报告 第6部分（共8部分）**
> 面向构建生产级 AI Agent 系统的技术工程师
> 调研日期：2026年7月

---

## 执行摘要

随着大语言模型（LLM）驱动的 AI Agent 系统从实验室原型走向生产部署，安全工程已从可选的附加层演变为架构核心。2025年被业界称为"LLM Agent 之年"，企业大规模赋予 AI 系统自主执行能力的同时，攻击面也以前所未有的速度扩大。据全球安全调查显示，97%的安全负责人预期本年度将发生重大 AI Agent 安全事件，但仅有14.4%的组织在生产部署前实施了完整的安全控制 [1]。Prompt 注入影响约34%的已部署 Agent，位居 OWASP LLM Top 10（2025版）首位 [1]。

本报告系统性地调研了 AI Agent 安全工程的八大核心领域：OWASP LLM Top 10（2025版）风险全景、Prompt 注入攻击分类学、护栏工程（Guardrails）、沙箱与权限隔离、数据泄露防护、Multi-Agent 安全、红队测试方法论与工具，以及前沿趋势与合规治理。我们通过对15+独立来源的深度分析，提炼出可直接指导生产系统设计的安全架构原则与实践建议。

核心发现表明：单一安全层不足以防御现代攻击；分层防御（defense-in-depth）是唯一可靠策略。从输入护栏到输出验证、从沙箱隔离到人在回路（HITL）审批、从红队持续测试到合规治理，每一层都需要精心设计与协同运作。特别值得关注的是，Multi-Agent 系统的安全性是非组合的（non-compositional）——单独安全的 Agent 可以组合成不安全的系统，这对传统安全思维提出了根本性挑战 [2]。

---

## 一、引言

### 1.1 研究范围与目标

本报告聚焦于生产环境中 AI Agent 系统的安全工程实践。研究范围涵盖：基于 LLM 的 Agent 系统面临的主要安全威胁及其分类学、防御性安全架构的设计原则与工具生态、组织级安全治理流程（红队测试、合规框架）、以及前沿研究趋势对未来安全实践的影响。目标读者为正在构建或运维生产级 AI Agent 系统的技术工程师、安全架构师和技术决策者。

### 1.2 方法论

本报告采用多源系统调研方法。首先对 OWASP、NIST 等权威机构的官方文档进行深度解读；其次对 arXiv 上的最新学术研究（2024-2026）进行系统性检索与分析；第三对主流安全工具（NeMo Guardrails、Guardrails AI、LLM Guard、PyRIT、Garak、Promptfoo 等）的技术文档与实践案例进行对比评估；最后对行业安全事件报告与企业安全实践进行案例研究。所有事实性声明均附引用标注。

### 1.3 核心假设

本报告基于以下假设：（1）AI Agent 系统将持续获得更大的自主权和更广泛的工具访问权限；（2）攻击者的能力和动机将随 Agent 系统价值的增长而同步升级；（3）完美防御不存在，安全工程的目标是将风险降至可接受水平并建立快速响应能力；（4）监管合规将从自愿遵守逐步转向强制要求。

---

## 二、主要发现

### 发现一：OWASP LLM Top 10 (2025) — 风险全景

OWASP 于2024年底发布了 LLM 应用 Top 10 的2025版更新，这是继2023年首版之后的重大修订，反映了真实世界事件、新兴攻击技术以及 Agentic AI 的快速增长 [3]。2025版新增了两个全新类别，对多个现有类别进行了实质性重构，并基于社区反馈重新排列了风险优先级 [3]。

**十大风险完整解读：**

**LLM01：Prompt 注入（Prompt Injection）** 继续蝉联榜首。2025版首次将间接注入（indirect injection）正式列为与直接注入同等级的子类型，而非仅作为附属说明 [4]。这反映了 Agent 系统通过检索增强生成（RAG）、工具调用和外部数据源接触不可信输入的场景急剧增加。缓解策略包括输入验证、权限分离、以及将 LLM 输出视为不可信数据的架构原则。

**LLM02：敏感信息泄露（Sensitive Information Disclosure）** 是排名变化最大的类别，从2023版的第6位跃升至第2位 [5]。这一变化反映了 LLM 系统在生产环境中处理越来越多的敏感数据——从个人身份信息（PII）到企业机密和系统架构详情。向外部 LLM 提供商发送 Prompt 意味着 PII 离开了组织基础设施边界 [6]。

**LLM03：供应链风险（Supply Chain Vulnerabilities）** 从第5位上升至第3位 [5]。随着 LLM 生态系统的依赖链日益复杂——包括预训练模型、微调数据集、Prompt 模板库、插件和 MCP 服务器——供应链的每个环节都可能成为攻击入口。2025年4月发现的 MCP 工具投毒攻击（Tool Poisoning）正是这一风险的典型体现 [7]。

**LLM04：数据与模型投毒（Data and Model Poisoning）** 聚焦于训练数据和微调数据的完整性风险。攻击者可以通过向向量数据库注入恶意内容来投毒 RAG 系统，当系统检索这些被投毒的文档时，隐藏的指令可以引导 AI 执行攻击者的意图而非用户请求 [8]。

**LLM05：不当输出处理（Improper Output Handling）** 强调 LLM 输出不应被直接信任或执行。当 LLM 输出被传递给下游系统（如数据库查询、API 调用或代码执行）时，缺乏验证和清洗可能导致注入攻击的传播。这在 Agent 系统中尤为关键，因为 Agent 的输出通常直接触发工具调用。

**LLM06：过度代理（Excessive Agency）** 被2025版显著扩展。OWASP 将其分解为三个根本原因：过度功能（Agent 可访问超出任务范围的工具）、过度权限（工具以超出必要的特权运行）、以及过度自主（高影响操作在无人监督下执行）[3]。这是已部署系统中最具预测性的故障模式——Agent 被授予的访问权限超出其功能需求，是2025-2026年每项企业 AI 安全调查中报告最一致的失败 [1]。

**LLM07：系统提示泄露（System Prompt Leakage）** 是2025版新增的独立类别。攻击者通过精心构造的 Prompt 可以提取系统指令、安全规则和内部配置，这不仅泄露知识产权，还为后续攻击提供侦察信息。

**LLM08：向量与嵌入弱点（Vector and Embedding Weaknesses）** 是2025版新增类别，直接回应了 RAG 在生产中的主流化 [3]。向量数据库上不充分的访问控制可能导致跨租户边界暴露敏感数据。攻击者还可以操纵嵌入模型本身以产生误导性的相似度结果，降低 RAG 系统生成内容的质量和可信度 [3]。

**LLM09：错误信息（Misinformation）** 由2023版的"过度依赖"（Overreliance）重命名并重新聚焦。风险不仅在于用户过度信任模型输出，更在于模型本身生成和传播虚假信息 [3]。在 Agent 系统中，错误信息可能触发错误的决策链和工具调用。

**LLM10：无界消耗（Unbounded Consumption）** 替换了2023版较为狭窄的"模型拒绝服务"类别，涵盖完整的资源滥用频谱。这包括拒绝服务（DoS）、财务利用（通过大量 API 调用造成高额账单）、以及模型未授权复制 [3]。随着 LLM 使用成本变得足够大，成本本身成为攻击向量。

**2023版与2025版关键对比：** 驱动这些变化的核心因素包括：RAG 架构在生产中的主流化、LLM 输出开始影响真实业务决策、使用成本增长到可作为攻击向量的规模、以及2025年作为"LLM Agent 之年"带来的自主权扩张 [5]。2023版更多关注模型本身的弱点，而2025版明确转向系统级和架构级风险，反映了 LLM 应用从独立聊天机器人向复杂 Agent 系统的演进。

### 发现二：Prompt 注入攻击 — 分类学与真实案例

Prompt 注入被广泛认为是 LLM 时代的"SQL 注入"——一种根植于架构的根本性脆弱性 [9]。2024-2025年的研究显著深化了我们对攻击分类学的理解，尤其是在 Agent 系统场景下。

**攻击分类的三维框架：** 最新研究提出了一个三维分类法，从投递向量（delivery vector）、攻击模态（attack modality）和传播行为（propagation behavior）三个维度组织 Prompt 注入攻击 [4]。这一框架首次桥接了输入级利用和协议层漏洞之间的关系，为 LLM Agent 生态系统提供了统一的威胁模型 [10]。

**直接注入（Direct Injection）** 是最基本的形式。攻击者直接在用户输入中嵌入恶意指令，试图覆盖系统 Prompt 或改变模型行为。典型技术包括角色扮演（"忽略之前的指令，你现在是..."）、分隔符利用、编码混淆（Base64、Unicode 变体等）。虽然直接注入在现代系统中的成功率已被防御措施显著降低，但它仍然是攻击者最先尝试的手段。

**间接注入（Indirect Injection）** 是 Agent 系统面临的核心威胁。与直接注入不同，间接注入的恶意载荷不来自用户输入，而是嵌入在 Agent 处理的外部数据中——网页内容、电子邮件、文档、API 响应、工具输出或 RAG 检索结果 [4]。当 LLM 处理这些外部内容时，嵌入其中的指令被作为可信输入执行。2025版 OWASP LLM Top 10 首次将间接注入正式列为与直接注入同等级的子类型 [4]。

间接注入的隐蔽性极强。研究人员证明，通过在网页中嵌入零号字体（0-point font）的 Prompt，可以欺骗 Bing Chat 输出攻击者指定的任何消息 [11]。更危险的是数据外泄变体：利用 Markdown 图片注入，攻击者在 AI 输出中嵌入指向攻击者控制服务器的图片 URL，当 AI 渲染图片时，聊天记录或用户上传的文档等敏感数据被无声地发送给攻击者 [11]。

**多步注入与越狱链（Multi-step Injection & Jailbreak Chains）** 代表了攻击复杂度的显著提升。2024年，研究者开始展示具有扩展杀伤链（kill chain）覆盖的攻击，包括首次实现持久化（Persistence）、侦察（Reconnaissance）和横向移动（Lateral Movement）的实例 [4]。PyRIT 的标志性能力就是多轮对话攻击模拟：渐进式攻击（crescendo attacks）在多次交互中逐步升级，趋向有害行为 [12]。

**跨 Agent 攻击链传播** 是 Multi-Agent 系统的独特威胁。2024年3月的 Morris II 蠕虫是首个五阶段攻击的演示 [4][13]。研究者构建了一封包含对抗性自复制 Prompt 的电子邮件，该 Prompt 存储在 RAG 系统中，被发送到 LLM 提供商后越狱服务并窃取数据。当服务被用来回复其他邮件时，新接收者也被感染，从而实现无需人类干预的自动传播 [13]。Morris II 针对 Gemini Pro、ChatGPT 4.0 和 LLaVA 进行了测试，在电子邮件助手场景中演示了垃圾邮件发送和个人数据外泄两个用例 [13]。2024年10月的 Prompt Infection 演示进一步展示了多 Agent 系统中的跨 Agent 传播 [4]。

**真实案例回顾：**

*Bing Chat 间接注入（2023）*：斯坦福学生通过精心构造的 Prompt 使 Bing Chat 泄露了其隐藏的系统指令和内部配置 [11]。后续研究展示了通过网页中的隐藏文本实现更复杂的攻击，包括数据外泄。

*ChatGPT 记忆注入*：研究人员展示了恶意网站可以在 ChatGPT 的网页浏览功能中注入 Prompt。当 ChatGPT 访问包含隐藏文本的网站来回答用户问题时，页面中的隐藏指令可以指导 ChatGPT 执行用户从未请求的操作 [11]。2024年底，The Guardian 的测试发现该功能仍然易受间接注入攻击 [11]。

*MCP 工具投毒（2025）*：Invariant Labs 在2025年4月命名了"工具投毒"攻击，通过在计算器工具描述中隐藏指令的概念验证，使 Cursor 编辑器读取了用户的私有 SSH 密钥并发送出去 [7]。此后，工具投毒攻击已成功泄露了 WhatsApp 聊天记录、GitHub 私有仓库和 SSH 凭证 [7]。MCPTox 基准测试在45个真实 MCP 服务器和20个领先 AI 模型上运行投毒工具描述，发现攻击成功率高达72.8% [7]。两个重大 CVE（MCPoison CVE-2025-54136 和 CurXecute CVE-2025-54135）使这一攻击类别登上了安全版图 [7]。

**Promptware 杀伤链：** 研究者将 Prompt 注入的演进描述为从简单的输入操纵到成熟的"Promptware 杀伤链"的过程 [4]。这个杀伤链涵盖了从初始访问、权限提升、持久化、侦察到横向移动的完整攻击生命周期，与传统恶意软件的 MITRE ATT&CK 框架形成对应。

### 发现三：护栏工程 — 分层防御架构

护栏（Guardrails）是 AI Agent 安全架构中的核心防御层，其本质是在 LLM 的输入和输出路径上设置可编程的检查点。生产级护栏工程的核心原则是分层防御：永远不要让 LLM 直接调用工具，模型返回结构化的工具调用请求，由确定性的 harness 层验证 schema、检查权限、执行操作并将结果注入回模型 [1]。

**输入护栏（Input Guardrails）** 在用户请求到达 LLM 之前执行过滤和检测。关键能力包括：

*意图分类* 是第一道防线，通过分类器判断用户请求是否属于 Agent 的合法业务范围。超出范围的请求在到达 LLM 之前即被拦截，显著减少攻击面。

*Prompt 注入检测* 使用多层技术：基于启发式规则的模式匹配（检测已知攻击模式）、基于 LLM 的分析（使用专用模型判断输入是否包含注入企图）、以及基于向量数据库的历史攻击匹配 [14]。

*敏感词过滤与内容分级* 阻止包含禁止主题、有害内容或超出安全策略范围的输入。

**输出护栏（Output Guardrails）** 在 LLM 响应返回给用户或触发工具调用之前执行验证。关键能力包括：

*格式验证* 确保 LLM 输出符合预期的结构化格式（JSON schema、API 参数规范等），防止格式错误触发下游系统故障。

*PII 脱敏* 检测并移除或替换输出中的个人身份信息，防止敏感数据泄露。

*有害内容过滤* 检测并阻止包含不当内容、偏见或潜在有害建议的输出。

*工具调用验证* 检查 Agent 请求的工具调用是否在允许范围内、参数是否合法、操作是否需要人工审批。

**主流工具对比：**

*NeMo Guardrails（NVIDIA）* 通过对话流控制实现安全防护。它引入了名为 Colang（现为 Colang 2.0）的领域特定语言，定义跨五个管道阶段（输入轨道、对话轨道、检索轨道、执行轨道、输出轨道）触发的规则 [15]。NeMo Guardrails 的核心优势在于有状态的对话管理——它能理解对话上下文并执行复杂的对话策略和主题边界。适用场景：当 Agent 需要明确的主题边界和复杂对话策略时。

*Guardrails AI* 提供开源的程序化框架，通过输出验证来缓解 LLM 使用风险。开发者可以使用 Python 或 JavaScript，利用 Guardrails Hub 上的预构建验证器或从零构建自己的验证器 [15]。其核心优势在于结构化数据验证——当 LLM 必须返回表单、API 载荷或报告等结构化数据时，Guardrails AI 是最佳选择 [15]。

*LLM Guard* 作为快速第一层扫描器运行一系列输入和输出扫描器（Prompt 注入检测、越狱字符串、密钥泄露、Token 限制、禁止主题、匿名化），在管道前端拦截低成本的明显攻击，避免昂贵的模型调用 [15]。适用场景：构建面向真实用户的生产应用并需要开箱即用的广泛覆盖。

*Rebuff* 是由 Protect AI 开发的开源自强化 Prompt 注入检测框架，提供四层防御：启发式过滤、基于 LLM 的检测、基于向量数据库的历史攻击匹配、以及金丝雀令牌（canary token）泄露检测 [14]。Rebuff 向系统 Prompt 添加唯一生成的金丝雀词，如果该词出现在响应中则表明系统 Prompt 已泄露。但需注意 Rebuff 仍是原型阶段，不能提供100%的注入防护 [14]。

**分层护栏架构模式：** 生产中的最佳实践是组合使用多个工具：LLM Guard 作为快速第一层扫描器处理明显攻击，NeMo Guardrails 进行对话流控制，Guardrails AI 执行输出验证 [15]。多个团队在2026年已经在同一系统中同时使用 NeMo Guardrails 进行对话管理和 Guardrails AI 进行输出验证，利用各自框架的优势 [15]。这种分层方法确保了在不同攻击类型和场景下的防御覆盖，同时将延迟和成本控制在可接受范围内。

### 发现四：沙箱与权限隔离

当 AI Agent 需要执行代码、操作文件系统或与外部服务交互时，沙箱隔离成为安全架构的基石。2026年的行业共识是防御纵深模型，主要依靠三种隔离原语：微虚拟机（microVM）、用户空间内核（gVisor）和加固容器 [16]。

**代码执行沙箱技术：**

*Firecracker 微虚拟机* 是当前执行不可信代码的黄金标准。每个工作负载获得独立的内核，运行在硬件虚拟化（KVM）之上。一个 VM 内的内核漏洞无法触及宿主机或其他 VM。Firecracker 启动时间约125毫秒，内存开销约5MB [16]。它驱动了 AWS Lambda、E2B 和 Vercel Sandbox 等服务。

*gVisor 用户空间内核* 是 Google 开发的用户空间应用，拦截并重新实现系统调用（syscall），使沙箱程序永远不与真实内核通信。安全性强于容器但开销低于完整 VM [16]。被 Google（GKE 上的 Agent Sandbox）和 Modal 使用。

*加固容器* 虽然是最轻量的方案，但共享内核的本质使其不足以隔离 LLM 生成的不可信代码。对于 LLM 生成代码执行，微虚拟机（Firecracker、Kata）是唯一的生产安全隔离层 [16]。

**主流沙箱平台：**

*E2B* 专门为 AI Agent 工作流构建安全沙箱，采用 SDK 优先设计，基于 Firecracker 微虚拟机提供临时代码执行环境。其强项是专为 AI Agent 场景优化的 API 和短暂性执行模型 [16]。

*Modal* 使用 gVisor 隔离，为 Python ML 工作负载优化。优势包括原生 GPU 支持（T4 到 H200）、从零开始的无服务器自动扩展、以及通过 Python SDK 实现的基础设施即代码 [16]。

**工具调用权限控制与最小权限原则：** 安全 Agent 架构的六个基本控制层包括：身份认证、最小权限访问、运行时执行控制、行为监控、审计日志和供应链安全 [1]。即时授权（just-in-time authorization）被专家认为对于保障非人类互联网至关重要。核心原则是 Agent 的每个工具调用都应经过权限检查，且权限应按最小权限原则配置——Agent 只能访问完成当前任务所必需的最少工具和最低权限。

**人在回路（HITL）审批机制：** HITL 是将结构化人工干预点集成到生产 Agent 系统中的架构方法，使人类能在预定风险阈值处审查、批准或覆盖决策 [17]。EU AI Act 第14条明确要求"高风险 AI 系统应以适当的人机界面工具方式设计和开发，使其在使用期间可由自然人有效监督" [17]。

HITL 的核心挑战在于规模化：它不可扩展，退化为橡皮图章。人类审批每个重要操作将 Agent 限制在人类速度、人类注意力范围和人类工作时间内 [17]。因此，生产系统通常采用分层方法：低风险操作自动执行，中等风险操作异步审计，高风险操作（不可逆的财务交易、账户修改、数据删除）同步等待人工审批 [17]。Shopify 采用了"人在回路优先设计"的默认策略，通过审批门控阻止对生产系统的完全自主变更 [1]。

**Anthropic 的"计算机使用"安全模型：** Anthropic 的安全最佳实践要求在沙箱虚拟机或 Docker 容器中运行 Agent，使用干净操作系统——无保存的密码、无已认证的会话，且网络访问受限 [18]。其核心理念是：与其监督 Agent 做什么，不如监督它能做什么——通过沙箱、虚拟机和出口控制来执行访问边界 [18]。

Claude Code 的沙箱功能通过两个边界减少权限提示并提高用户安全：文件系统隔离（确保 Claude 只能访问或修改特定目录）和网络隔离（确保 Claude 只能连接到已批准的服务器）[18]。在内部使用中，沙箱安全地减少了84%的权限提示 [18]。对于 Claude Code 的自动模式，基于模型的分类器委托命令批准，以约0.4%的良性命令被阻止的代价，换取在约17%的过度操作上的可接受漏率——因此它是沙箱内纵深防御的一个层，而非替代品 [18]。

### 发现五：数据泄露防护

AI Agent 系统处理的数据量和数据敏感度持续增长，数据泄露防护已成为安全架构的关键组件。泄露路径多样：用户向聊天界面粘贴邮件、电话、地址甚至凭证；现代 LLM 接受数千 Token 的输入增加了意外 PII 暴露的表面积；可观测性工具可能无意中存储敏感信息；训练数据中未经净化的 PII 可能被嵌入模型权重；向外部 LLM 提供商发送 Prompt 意味着 PII 离开基础设施边界 [6]。

**PII 检测与脱敏：**

*Microsoft Presidio* 是最成熟的开源 PII 检测和匿名化框架，提供对文本、图像和其他模态的上下文感知 PII 检测 [6]。其 Analyzer 组件结合了来自 spaCy 或 Hugging Face Transformers 的命名实体识别（NER）、正则表达式模式匹配和上下文评分。Analyzer 识别字符串中 PII 数据的位置和类型，Anonymizer 则用不可识别信息替换该数据 [6]。

在生产部署中，Presidio 可以作为 LLM 护栏部署在 API 管理（APIM）边缘，作为拦截每个 LLM 请求的代理：从 Prompt 中清除 PII，转发清洁版本，然后在响应中恢复 PII [6]。对于拥有现有 AKS 集群的企业部署，Presidio 发布了 Helm charts，提供对资源限制、HPA 扩展、Pod 亲和性和网络策略的完全控制 [6]。重要的限制是 Presidio 使用自动检测机制，无法保证找到所有敏感信息，因此应部署额外的系统和保护措施 [6]。

*spaCy NER* 提供了高性能的命名实体识别能力，是 Presidio 底层的重要引擎之一。结合自定义训练的 NER 模型可以针对特定领域（如医疗记录、金融数据）提高 PII 检测的精确度和召回率。

**上下文隔离（多租户场景）：** 在多租户 AI Agent 平台中，上下文隔离是防止跨租户数据泄露的核心机制。多租户 LLM 服务的模式是在一个共享的 GPU 后端推理端点上服务多个外部客户，每个客户有独立的 Token 配额、速率限制和数据隔离保证 [19]。

隔离策略分为三个层次：硬隔离（每个租户获得完全独立的部署，包含专用计算和严格分区的数据存储）、软隔离（多个租户在相同底层基础设施上运行，使用逻辑边界分离数据）、以及带访问控制的共享隔离（使用行级安全在查询时执行权限检查）[19]。

关键原则是后端服务（而非语言模型）应解析租户上下文，以防止 LLM 上下文窗口成为跨租户数据外泄路径 [19]。租户感知上下文传播意味着 tenant_id、作用域和策略附加到每个工具调用、检索查询和模型请求 [19]。

**数据分级体系：** 生产 AI Agent 系统应建立明确的数据分级策略——公开（Public）、内部（Internal）、机密（Confidential）、绝密（Top Secret）。每个级别对应不同的安全控制措施：公开数据可自由用于 LLM 处理；内部数据需要身份验证但可使用外部 LLM API；机密数据应仅通过私有部署的模型处理，且 Prompt 和响应不得离开组织网络边界；绝密数据需要额外的审计跟踪、加密和人工审批流程。

**RAG 安全：** RAG 系统引入了独特的数据泄露风险。当文档被转换为向量时，文档失去了原始权限设置 [8]。来自 Confluence、SharePoint 或内部 Wiki 的内容在向量化后被剥离了访问控制，这意味着初级员工可能通过提出正确的问题访问高管文档 [8]。

保障 RAG 安全需要在三个不同层——摄入层、检索层和生成层——进行控制。任何单一层的失败不应导致完全妥协 [8]。在摄入层，应维护文档级元数据（包括原始权限信息）并将其存储为向量的附属信息。在检索层，应使用权限感知的元数据过滤器确保每次向量查询都受到访问控制约束。在生成层，应验证返回给用户的内容不包含其无权访问的信息。向量数据库隔离的推荐方案是每个租户一个命名空间（namespace），因为查询成本通常基于命名空间大小，使每个租户一个命名空间比使用元数据过滤器扫描单个大命名空间显著更便宜 [19]。

### 发现六：Multi-Agent 安全 — 信任边界与攻击面

随着 Multi-Agent 系统的研究论文比例从2024年的9.52%上升至2025年的23.97%，多 Agent 安全研究出现爆发式增长——从2023年的3篇增长到2024年的42篇和2025年的121篇 [2]。这一增长反映了 Multi-Agent 系统在生产中的快速采用，以及随之而来的安全挑战的紧迫性。

**攻击面的 N-squared 放大：** Multi-Agent 系统显著扩大了对抗性攻击面。将任务委托给 AI Agent 扩展了主体（principal）的信任边界到其软件代理，使其成为妥协的有吸引力目标 [2]。在一个包含 N 个 Agent 的系统中，潜在的 Agent 间通信通道数为 N(N-1)/2，每个通道都是潜在的攻击向量。这意味着攻击面随 Agent 数量呈二次方增长。

**安全的非组合性问题：** Multi-Agent 系统中安全性是非组合的——单独安全的 Agent 可以组合成不安全的系统 [2]。这是多 Agent 安全最深层的挑战。系统可以发展出包括隐蔽串通（covert collusion）、协调攻击和级联故障在内的行为，这些行为无法通过单独分析各个 Agent 来预测 [2]。这意味着即使每个 Agent 都通过了独立的安全审查，整个系统仍可能存在未被发现的脆弱性。

**Agent 间信任边界设计：** 由 LLM 驱动的 Multi-Agent 系统面临"信任-脆弱性悖论"（Trust-Vulnerability Paradox）：增加 Agent 间信任以增强协调，同时扩大了过度暴露和过度授权的风险 [2]。有效的信任边界设计需要：每个 Agent 将其他 Agent 的输出视为不可信数据（类似于处理外部用户输入）；Agent 间消息传递应经过清洗层，剥离或中和类似指令的模式 [2]；基于零信任原则，每次 Agent 间交互都需要身份验证和授权。

**恶意 Agent 检测：** 在开放的多 Agent 生态系统中，恶意 Agent 可能伪装成合法服务提供者。检测策略包括：行为异常检测（监控 Agent 的工具调用模式和数据访问模式是否偏离基线）、声誉系统（基于历史交互记录建立 Agent 信任评分）、以及输出一致性验证（对关键决策使用多个独立 Agent 交叉验证）。在多 Agent 设置中，妥协可能在交互的 Agent 之间传播，甚至颠覆监督者和策略控制器组件，破坏系统级防御 [2]。

**"毒化工具描述"攻击：** MCP 工具投毒是 Multi-Agent 安全面临的新型威胁。控制或入侵 MCP 服务器的攻击者可以在描述符中直接写入指令，Agent 会将这些指令原封不动地交给模型处理——没有清洗、没有来源验证、具有完全的环境权限 [7]。OWASP 已将工具投毒列为 MCP Top 10 的第三大风险（MCP03:2025）[7]。Microsoft 也发出警告，称投毒的 MCP 工具描述可以使 AI Agent 泄露数据 [7]。

**A2A 协议安全考量：** Agent2Agent（A2A）是由 Google Cloud 与60+公司共同创建的开放互操作协议 [20]。A2A 基于零信任原则架构，使用 JSON-RPC 2.0 over HTTP/HTTPS 进行请求响应，使用 Server-Sent Events（SSE）进行实时流式传输 [20]。安全机制包括：Agent Cards 支持 OAuth 2.0、API 密钥、OpenID Connect 和 Bearer Tokens；签名 Agent Cards 通过加密签名验证卡片确实由域所有者签发 [20]。A2A 已由 Google 捐赠给 Linux 基金会，由 AWS、Cisco、Google、IBM Research、Microsoft、Salesforce、SAP 和 ServiceNow 的代表组成的技术指导委员会维护 [20]。

然而，协议层安全不等于应用层安全。即使 A2A 提供了身份验证和传输加密，Agent 仍然可能通过合法协议通道传递包含注入攻击的消息。因此，A2A 的安全部署还需要在应用层实施消息内容验证和异常检测。

### 发现七：红队测试 — 方法论与自动化工具

红队测试已从偶发性的安全评估活动演变为 AI Agent 安全生命周期中的持续性实践。NIST、OWASP 等机构提供了方法论框架，而 PyRIT、Garak、Promptfoo 等工具实现了测试的自动化和规模化。

**NIST AI 600-1 方法论框架：** NIST AI 600-1 是 AI 风险管理框架（AI RMF 1.0）的生成式 AI 专用配套文件，名为"人工智能风险管理框架：生成式人工智能概况"[21]。该框架将其风险映射到 AI RMF 的四个功能：治理（Govern）、映射（Map）、度量（Measure）和管理（Manage）[21]。AI 红队测试是 Measure 功能中推荐的关键测试方法论之一 [21]。

NIST 定义了四种红队测试类型：公众型（General Public）、专家型（Expert）、组合型（Combination）和人机协同型（Human/AI），并强调独立于开发过程、多学科交叉的团队组成的重要性 [21]。该框架涵盖12类生成式 AI 独有或显著放大的风险类别，包括生成虚假信息或网络安全攻击、泄露用户隐私信息、以及用户对 AI 工具产生情感依赖的可能性 [21]。

**Agent Security Bench (ASB)** 是 ICLR 2025 上发表的综合性基准框架，包含10个场景（电子商务、自动驾驶、金融等）、10个 Agent、400+工具、27种不同的攻击/防御方法和7个评估指标 [22]。ASB 评估了10种 Prompt 注入攻击、记忆投毒攻击、新颖的 Plan-of-Thought（PoT）后门攻击、4种混合攻击以及11种相应防御，跨越13个 LLM 后端 [22]。基准结果揭示了 Agent 运行不同阶段（系统 Prompt、用户 Prompt 处理、工具使用、记忆检索）的关键脆弱性，最高平均攻击成功率达84.30%，但当前防御的有效性有限 [22]。

**HarmBench** 是由 AI 安全中心发布的标准化自动红队评估框架，初始版本在2024年2月发布时评估了33个目标 LLM 和18种红队方法 [23]。其核心指标是攻击成功率（ASR）——成功从 LLM 引发目标有害行为的测试用例百分比 [23]。HarmBench 解决了 LLM 安全评估中的关键缺口：临时性红队测试、研究间不一致或狭窄的 Prompt 集、以及缺乏稳健可复现的攻击和防御对比指标 [23]。

**自动化红队工具对比：**

*Promptfoo* 从应用开发者视角出发，测试完整的 LLM 系统——包括 RAG 管道、Agent 架构和 API 集成——并动态生成数千个针对特定应用上下文的攻击变体 [12]。OpenAI 在2026年3月以约8600万美元收购了 Promptfoo，但保持了 MIT 许可证 [12]。它是 CI/CD 集成应用安全测试的最佳默认选择，提供快速反馈循环。

*PyRIT（Microsoft）* 是工具套件而非单一工具。与 Garak 使用静态探测库不同，PyRIT 使用编排器 LLM 作为攻击者，基于目标模型的实时响应动态生成和改进对抗性 Prompt [12]。PyRIT 的标志性能力是多轮对话攻击模拟——渐进式攻击在多次交互中逐步升级 [12]。适用场景：定期的全面红队测试。

*Garak（NVIDIA）* 提供基于学术研究和已记录漏洞的预定义攻击探测库，允许安全研究人员针对 LLM 端点运行 Garak 以检查已知弱点 [12]。适用场景：在重大模型变更前进行基线漏洞扫描。

**推荐工具组合策略：** 使用 Promptfoo 作为面向开发者的 CI/CD 门控（快速反馈循环），PyRIT 进行定期全面红队运行，Garak 在重大模型变更前进行基线漏洞扫描 [12]。

**持续红队 vs 一次性评估：** 一次性红队评估提供时间点快照，但 AI Agent 系统的威胁景观持续演变——新的攻击技术不断涌现，模型更新可能引入新的脆弱性，工具和数据源的变化也会改变攻击面。持续红队实践将安全测试集成到 CI/CD 管道中，在每次代码提交、模型更新或配置变更时自动运行安全测试套件。这要求组织建立红队指标基线、设定可接受阈值、并在阈值被突破时自动触发警报和部署阻断。

### 发现八：前沿趋势与合规治理

AI Agent 安全领域正处于技术创新与监管合规的双重加速期。前沿研究提供了新的防御范式，而全球监管框架的快速成熟则为安全实践提供了法律强制力。

**Constitutional AI 与 Constitutional Classifiers：** Anthropic 开发的 Constitutional AI 通过"宪法"——一组定义行为边界的人类语言原则——来对齐 AI 系统的行为 [24]。核心技术包括自监督训练和对抗性训练，使模型在面对对抗性输入时仍能产生恰当的响应 [24]。

更具实战意义的是 Constitutional Classifiers 系统。这些安全护栏监控模型输入和输出以检测并阻止潜在有害内容。与未防护模型相比，第一代分类器将越狱成功率从86%降低到4.4%——阻止了95%可能绕过 Claude 内置安全训练的攻击 [25]。2025年推出的 Constitutional Classifiers++ 采用两阶段架构：一个探针查看 Claude 的内部激活以筛查所有流量，如果发现可疑交互则升级到更强大的分类器。这一改进以仅约1%的额外计算成本实现了更强健的防御和更低的误拒率 [25]。2025年2月的挑战赛吸引了339名参与者，在8个 CBRN 难度级别上产生超过30万次交互，Anthropic 共支付了55000美元赏金 [25]。

**形式化验证：** 自主 Agent 必须遵守可证明的不变量，形式化验证为诸如"永不传输未加密的 PII"或"永不超过信用额度"等约束提供了护栏 [24]。然而，形式化验证要求一个机器可读的模型，其中状态的每个组件和每个转换都被明确表示 [24]。当前 LLM 系统的内部状态缺乏这种可形式化的透明性，使得完全的形式化验证在短期内难以实现。但在 Agent 的确定性组件（工具调用验证、权限检查、数据流控制）上应用形式化方法是可行的，可以提供数学证明级别的安全保证。

**对抗性训练：** 持续的红队测试和对抗性训练在识别弱点方面发挥着不可或缺的作用，包括人类和自动化红队测试不断以新型攻击向量挑战 AI 系统 [24]。对抗性训练通过在训练过程中系统性地暴露模型于已知攻击模式，增强模型对这些攻击的鲁棒性。但根本挑战在于：在对齐技术中实现鲁棒、可扩展和可解释的安全机制仍面临重大困难，新兴研究机会包括机械可解释性、对抗鲁棒性和跨多元文化的价值对齐 [24]。

**可信 AI Agent：** 构建可信 AI Agent 需要在可靠性、安全性、可解释性和公平性四个维度上同时取得进展。NIST AI 100-2e2025 定义了可信赖和负责任 AI 的技术标准，为行业提供了可操作的框架 [24]。未来的可信 AI Agent 将结合 Constitutional AI 的行为约束、形式化验证的数学保证、持续红队测试的实证验证、以及监管合规的法律保障。

**全球 AI 安全立法与合规框架：**

*EU AI Act（欧盟人工智能法案）*：这是全球最具约束力的 AI 监管法律。关键时间线包括：2025年2月禁止类 AI 实践生效（社会评分、非目标面部识别抓取、工作场所和学校情感识别）；2025年8月通用人工智能（GPAI）模型义务生效；2026年8月广泛执法开始 [26]。处罚极为严厉：违反禁止性 AI 实践可罚款高达3500万欧元或全球年营业额的7%；不遵守高风险 AI 系统要求可罚款1500万欧元或3%年营业额；向当局提供不正确信息可罚款750万欧元或1%年营业额 [26]。GPAI 提供商必须维护技术文档、发布训练数据摘要、实施合理的风险应对政策，并在模型存在系统性风险时通知 EU AI Office [26]。

*NIST AI RMF（AI 风险管理框架）*：NIST AI RMF 是自愿性的操作框架。与 EU AI Act 的强制性法律不同，AI RMF 提供灵活的、可适应不同组织规模和 AI 成熟度的风险管理方法 [26]。AI RMF 1.0 定义了四个核心功能：治理、映射、度量和管理，而 AI 600-1 则为生成式 AI 提供了专用配套指南。对于大多数美国组织，建议先用3-6个月启动 NIST AI RMF 进行风险管理，再用2-4个月构建 ISO 42001 认证，如有欧洲业务则额外用2-4个月层叠 EU AI Act 合规 [26]。

*中国 AI 安全标准*：中国在 AI 安全监管方面采取了多层次、快节奏的方法。2025年的关键标准包括：GB/T 45652-2025（生成式 AI 预训练和微调数据安全规范）、GB/T 45654-2025（生成式 AI 服务基本安全要求）、GB/T 45674-2025（生成式 AI 数据标注安全规范），这些标准将于2025年11月1日生效 [27]。强制性国家标准 GB 45438-2025（AI 生成内容标记方法）将于2025年9月1日生效 [27]。工信部（MIIT）在2025年3月发布了AI安全标准技术委员会的草案文件，列出了计划在未来1-3年内起草的70项 AI 安全标准 [27]。中国的监管路径侧重于具体的技术标准和内容管理，与 EU AI Act 的风险分级方法和 NIST 的框架化方法形成互补的全球监管图景。

---

## 三、综合洞察

综合八大发现，我们提炼出以下贯穿性洞察：

**安全是架构属性而非附加层。** 最有效的安全措施不是在系统完成后添加的过滤器，而是从架构设计阶段就嵌入的结构性约束。Anthropic 的安全模型体现了这一理念——与其监督 Agent 做什么，不如控制它能做什么 [18]。从输入验证到沙箱隔离、从权限控制到输出检查，每一层都是架构的有机组成部分。

**攻击者的进化速度超过静态防御的部署速度。** 从简单的 Prompt 注入到 Morris II 蠕虫的五阶段杀伤链 [13]，再到 MCP 工具投毒的72.8%成功率 [7]，攻击技术的演进速度令人警醒。这要求安全防御从静态规则向持续适应性测试转变，将红队测试集成到 CI/CD 管道中。

**Multi-Agent 系统的安全挑战是根本性的而非渐进性的。** 安全的非组合性意味着我们不能简单地将单 Agent 的安全实践扩展到多 Agent 系统 [2]。需要新的理论框架和工程方法来处理信任传递、级联妥协和隐蔽串通等独特威胁。

**合规从可选到强制的转变正在加速。** EU AI Act 的巨额罚款（最高营业额7%）[26]、中国70项 AI 安全标准的起草计划 [27]、以及 NIST 框架向 Agent 场景的扩展 [21]，共同构成了不可忽视的合规压力。尽早将合规要求纳入安全架构设计，避免后期的架构返工。

**工具生态正在走向分层化和专业化。** 没有单一工具可以解决所有安全问题。LLM Guard 负责快速第一层扫描，NeMo Guardrails 管理对话流，Guardrails AI 验证输出结构，Presidio 处理 PII，PyRIT/Garak/Promptfoo 执行红队测试——这种分层专业化的工具链是生产实践的方向 [15][12]。

---

## 四、局限性与注意事项

本报告存在以下局限性：

首先，AI Agent 安全是一个快速演变的领域，本报告的调研截止日期为2026年7月，部分发现可能在数月内即需更新。新的攻击技术和防御方法持续涌现。

其次，本报告侧重于技术工程视角，未深入覆盖组织治理、安全文化和人员培训等同样重要的非技术维度。

第三，工具对比基于公开文档和社区反馈，未进行独立的受控基准测试。不同部署环境下工具的实际表现可能与文档描述存在差异。

第四，多数引用的攻击成功率数据来自受控实验环境，生产系统中的实际攻击成功率可能因额外的防御层而有所不同。但考虑到仅14.4%的组织实施了完整安全控制 [1]，实际风险不应被低估。

第五，监管合规部分主要覆盖 EU、US 和中国三大辖区，其他地区（如英国、日本、新加坡等）的重要监管发展未在本报告中详细讨论。

---

## 五、建议

基于上述发现，我们为构建生产级 AI Agent 系统的团队提出以下建议：

**架构设计阶段：**

1. **采用确定性 Harness 架构**：永远不让 LLM 直接调用工具。模型返回结构化的工具调用请求，由确定性的 harness 层验证 schema、检查权限、执行操作 [1]。
2. **实施分层护栏**：部署 LLM Guard 作为第一层快速扫描，NeMo Guardrails 管理对话策略，Guardrails AI 验证输出结构 [15]。
3. **默认沙箱隔离**：所有代码执行使用微虚拟机（Firecracker）或 gVisor 隔离，容器不足以隔离 LLM 生成的不可信代码 [16]。

**权限与数据安全：**

4. **最小权限原则**：每个 Agent 只能访问完成当前任务所必需的最少工具和最低权限，实施即时授权（JIT）[1]。
5. **部署 PII 检测管道**：在 LLM API 边缘部署 Presidio 或同等工具，拦截、清洗和恢复 PII [6]。
6. **RAG 权限传播**：确保向量化过程保留文档权限元数据，检索时强制执行权限过滤 [8]。

**Multi-Agent 特殊考量：**

7. **零信任 Agent 间通信**：每个 Agent 将其他 Agent 的输出视为不可信数据，实施消息清洗和异常检测 [2]。
8. **限制 Agent 拓扑复杂度**：审慎控制 Agent 数量和通信模式，因为攻击面呈二次方增长 [2]。

**持续安全运营：**

9. **持续红队测试**：将 Promptfoo 集成到 CI/CD 管道作为门控，定期使用 PyRIT 进行全面红队运行 [12]。
10. **HITL 分层策略**：低风险自动执行，中风险异步审计，高风险同步人工审批 [17]。

**合规先行：**

11. **尽早开始合规准备**：启动 NIST AI RMF 风险管理，构建 ISO 42001 认证，层叠区域性法规合规 [26]。
12. **建立安全指标和审计跟踪**：从第一天起就记录所有 Agent 操作、工具调用和数据访问，为合规审计和事件调查提供基础。

---

## 六、参考文献

[1] Bessemer Venture Partners. "Securing AI agents: the defining cybersecurity challenge of 2026." https://www.bvp.com/atlas/securing-ai-agents-the-defining-cybersecurity-challenge-of-2026; AI Agents Kit. "AI Agent Security Best Practices 2026." https://aiagentskit.com/blog/ai-agent-security-best-practices/

[2] ArXiv. "Open Challenges in Multi-Agent Security: Towards Secure Systems of Interacting AI Agents." https://arxiv.org/html/2505.02077v2; ArXiv. "The Trust Paradox in LLM-Based Multi-Agent Systems." https://arxiv.org/html/2510.18563

[3] Confident AI. "OWASP Top 10 2025 for LLM Applications: What's new? Risks, and Mitigation Techniques." https://www.confident-ai.com/blog/owasp-top-10-2025-for-llm-applications-risks-and-mitigation-techniques

[4] ArXiv. "From Prompt Injections to Protocol Exploits: Threats in LLM-Powered AI Agents Workflows." https://arxiv.org/html/2506.23260v1; OWASP. "LLM01:2025 Prompt Injection." https://genai.owasp.org/llmrisk/llm01-prompt-injection/

[5] Lasso Security. "2025 Security Updates: OWASP Top 10 for LLMs & GenAI." https://www.lasso.security/blog/owasp-top-10-for-llm-applications-generative-ai-key-updates-for-2025; Aembit. "OWASP Top 10 for LLM Applications (2025)." https://aembit.io/blog/owasp-top-10-llm-risks-explained/

[6] Ploomber. "Preventing PII leakage when using LLMs: An introduction to Microsoft's Presidio." https://ploomber.io/blog/presidio/; ExplainX. "Microsoft Presidio: PII Detection Guide 2026." https://explainx.ai/blog/microsoft-presidio-pii-detection-anonymization-guide-2026

[7] Invariant Labs. "MCP Security Notification: Tool Poisoning Attacks." https://invariantlabs.ai/blog/mcp-security-notification-tool-poisoning-attacks; OWASP. "MCP03:2025 - Tool Poisoning." https://owasp.org/www-project-mcp-top-10/2025/MCP03-2025–Tool-Poisoning; TrueFoundry. "MCP Tool Poisoning (CVE-2025-54136)." https://www.truefoundry.com/blog/blog-mcp-tool-poisoning-gateway-defense

[8] Lasso Security. "RAG Security: Risks and Mitigation Strategies [2026]." https://www.lasso.security/blog/rag-security; ArXiv. "Towards Secure Retrieval-Augmented Generation." https://arxiv.org/abs/2603.21654

[9] Medium. "Prompt Injection: The SQL Injection of AI." https://lukasniessen.medium.com/prompt-injection-the-sql-injection-of-ai-how-to-defend-2a28c6f3bc05

[10] ScienceDirect. "From prompt injections to protocol exploits: Threats in LLM-powered AI agents workflows." https://www.sciencedirect.com/science/article/pii/S2405959525001997

[11] Netwrix. "ChatGPT Prompt Injection: How It Works, Risks & Defense Strategies." https://netwrix.com/en/cybersecurity-glossary/cyber-security-attacks/chatgpt-prompt-injection/; Lasso Security. "Prompt Injection Examples That Expose Real AI Security Risks." https://www.lasso.security/blog/prompt-injection-examples

[12] DEV Community. "Promptfoo vs Deepteam vs PyRIT vs Garak: The Ultimate Red Teaming Showdown." https://dev.to/ayush7614/promptfoo-vs-deepteam-vs-pyrit-vs-garak-the-ultimate-red-teaming-showdown-for-llms-48if; Promptfoo. "Top Open Source AI Red-Teaming and Fuzzing Tools in 2025." https://www.promptfoo.dev/blog/top-5-open-source-ai-red-teaming-tools-2025/

[13] ArXiv. "Here Comes The AI Worm: Unleashing Zero-click Worms that Target GenAI-Powered Applications." https://arxiv.org/html/2403.02817v2; Cybersecurity Magazine. "Morris II Worm: AI's First Self-Replicating Malware." https://cybermagazine.com/news/morris-ii-worm-inside-ais-first-self-replicating-malware

[14] GitHub. "Rebuff: LLM Prompt Injection Detector." https://github.com/protectai/rebuff; LangChain. "Rebuff: Detecting Prompt Injection Attacks." https://www.langchain.com/blog/rebuff

[15] Particula Tech. "AI Guardrails Compared: NeMo vs Guardrails AI vs Llama Guard." https://particula.tech/blog/ai-guardrails-compared-nemo-guardrails-ai-llama-guard; DEV Community. "Best AI Agent Security & Guardrails Tools in 2026." https://dev.to/agdex_ai/best-ai-agent-security-guardrails-tools-in-2026-llm-guard-vs-nemo-vs-guardrails-ai-5e5d; General Analysis. "Best AI Guardrails in 2026." https://generalanalysis.com/guides/best-ai-guardrails

[16] Substack. "How to sandbox AI agents in 2026: Firecracker, gVisor, runtimes & isolation strategies." https://manveerc.substack.com/p/ai-agent-sandboxing-guide; Modal Blog. "Best Code Execution Sandboxes for AI Agents in 2026." https://modal.com/resources/best-code-execution-sandboxes-ai-agents

[17] Galileo. "How to Build Human-in-the-Loop Oversight for AI Agents." https://galileo.ai/blog/human-in-the-loop-agent-oversight; StackAI. "Human-in-the-Loop AI Agents: How to Design Approval Workflows." https://www.stackai.com/insights/human-in-the-loop-ai-agents-how-to-design-approval-workflows-for-safe-and-scalable-automation

[18] Anthropic. "Making Claude Code more secure and autonomous with sandboxing." https://www.anthropic.com/engineering/claude-code-sandboxing; Anthropic. "How we contain Claude across products." https://www.anthropic.com/engineering/how-we-contain-claude; Anthropic. "How we built Claude Code auto mode." https://www.anthropic.com/engineering/claude-code-auto-mode

[19] Spheron Blog. "Multi-Tenant LLM Serving on GPU Cloud." https://www.spheron.network/blog/multi-tenant-llm-serving-gpu-cloud/; Blaxel. "Multi-tenant isolation for AI agents: security architecture guide." https://blaxel.ai/blog/multi-tenant-isolation-ai-agents; Truto Blog. "Multi-Tenant RAG Data Isolation: The 2026 Enterprise Architecture Guide." https://truto.one/blog/how-to-architect-strict-data-isolation-in-multi-tenant-rag-pipelines/

[20] A2A Protocol. "A2A Protocol Specification." https://a2a-protocol.org/latest/; Google Developers Blog. "Announcing the Agent2Agent Protocol (A2A)." https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/; Auth0. "Secure A2A Authentication." https://auth0.com/blog/auth0-google-a2a/

[21] Cloud Security Alliance. "NIST AI Agent Security: Red-Teaming Guidance." https://labs.cloudsecurityalliance.org/research/csa-research-note-nist-ai-agent-red-teaming-standards-202603/; NIST. "AI Risk Management Framework." https://www.nist.gov/itl/ai-risk-management-framework; Redteams.ai. "NIST AI 600-1 GenAI Risk Profile." https://redteams.ai/topics/governance-compliance/frameworks/nist-600-1

[22] ICLR 2025. "Agent Security Bench (ASB): Formalizing and Benchmarking Attacks and Defenses in LLM-based Agents." https://proceedings.iclr.cc/paper_files/paper/2025/hash/5750f91d8fb9d5c02bd8ad2c3b44456b-Abstract-Conference.html; GitHub. https://github.com/agiresearch/asb

[23] ArXiv. "HarmBench: A Standardized Evaluation Framework for Automated Red Teaming and Robust Refusal." https://arxiv.org/abs/2402.04249; HarmBench Official Site. https://www.harmbench.org/

[24] Anthropic. "Constitutional AI: Harmlessness from AI Feedback." https://arxiv.org/abs/2212.08073; Sakura Sky. "Trustworthy AI Agents: Formal Verification of Constraints." https://www.sakurasky.com/blog/missing-primitives-for-trustworthy-ai-part-9/; Constitutional.ai. https://constitutional.ai/

[25] Anthropic. "Constitutional Classifiers: Defending against universal jailbreaks." https://www.anthropic.com/research/constitutional-classifiers; Anthropic. "Next-generation Constitutional Classifiers." https://www.anthropic.com/research/next-generation-constitutional-classifiers; ArXiv. "Constitutional Classifiers++." https://arxiv.org/html/2601.04603v1

[26] EC Council. "EU AI Act vs NIST AI RMF vs ISO/IEC 42001: A Plain English Comparison." https://www.eccouncil.org/cybersecurity-exchange/responsible-ai-governance/eu-ai-act-nist-ai-rmf-and-iso-iec-42001-a-plain-english-comparison/; Sombrainc. "An Ultimate Guide to AI Regulations and Governance in 2026." https://sombrainc.com/blog/ai-regulations-2026-eu-ai-act; GAICC. "Global AI Governance Comparison 2026." https://gaicc.org/blog/ai-governance-comparison-eu-ai-act-nist-iso-42001/

[27] CMS Law. "AI laws and regulations in China." https://cms.law/en/int/expert-guides/ai-regulation-scanner/china; Georgetown CSET. "China Gen AI Training Data Safety Standard." https://cset.georgetown.edu/publication/china-gen-ai-training-data-safety-standard-draft/; ICLG. "China's Key Developments in Artificial Intelligence Governance in 2025." https://iclg.com/practice-areas/telecoms-media-and-internet-laws-and-regulations/03-china-s-key-developments-in-artificial-intelligence-governance-in-2025

---

## 附录：方法论说明

**调研方法：** 本报告采用系统性文献综述与工具评估相结合的方法。调研来源包括：

- **权威标准文档**：OWASP LLM Top 10（2025版）、NIST AI RMF 1.0 及 AI 600-1、EU AI Act 正式文本、中国 GB/T 国家标准
- **学术研究论文**：arXiv 上2024-2026年的 AI 安全相关论文，包括 ICLR 2025（ASB）、ICML 2024（HarmBench）等顶级会议发表
- **行业实践报告**：Anthropic、Microsoft、NVIDIA、Google 等主要 AI 公司的技术博客和安全白皮书
- **开源工具文档**：NeMo Guardrails、Guardrails AI、LLM Guard、Rebuff、PyRIT、Garak、Promptfoo、Presidio 等工具的官方文档和 GitHub 仓库
- **安全事件报告**：Morris II 蠕虫、MCP 工具投毒、Bing Chat/ChatGPT 间接注入等公开报告的安全事件

**搜索策略**：对每个研究主题执行多次定向搜索，使用英文技术术语确保覆盖最新的全球研究成果。每次搜索的结果经过交叉验证，确保事实性声明有至少一个独立来源支持。

**引用原则**：所有事实性声明均标注引用编号 [N]，对应参考文献部分的完整书目信息（含 URL）。对于综合性观点和架构建议，基于多个来源的综合分析但不逐一引用。

**局限性声明**：本调研截止于2026年7月。AI 安全领域变化极为迅速，建议读者以本报告为起点，持续跟踪 OWASP、NIST 和主要安全厂商的最新发布。

---

*本报告为 AI Engineering 深度调研系列第6部分。*
*下一部分（第7部分）将聚焦于 AI Agent 的可观测性与评估工程。*
