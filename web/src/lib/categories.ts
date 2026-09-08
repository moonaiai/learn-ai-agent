/**
 * The only hand-maintained configuration in the docs site.
 *
 * `scripts/extract-docs.ts` discovers every .md and .pdf under `docs/`
 * automatically — adding a new document requires no changes here. This file
 * only decides how the discovered topics are *grouped* and lets you override a
 * title or summary when the source Markdown can't supply a good one.
 *
 * A topic missing from every category lands in the trailing "其他" group and the
 * extractor prints a warning, so nothing silently disappears from the site.
 */

export interface Category {
  id: string;
  label: string;
  blurb: string;
  topics: string[];
}

export const CATEGORIES: Category[] = [
  {
    id: "llm-basics",
    label: "大模型基础",
    blurb:
      "Transformer 结构、注意力机制、位置编码、采样、KV Cache 与微调方法——AI Agent 开发岗面试高频的底层原理。",
    topics: [
      "transformer",
      "gpt",
      "tokenization",
      "positional-encoding",
      "sampling",
      "kv-cache",
      "lora",
      "qlora",
      "embedding",
      "llm-alignment",
    ],
  },
  {
    id: "agent-design",
    label: "Agent 设计原则",
    blurb:
      "Agent 与 workflow 的边界、控制流、工具接口设计——决定一个 Agent 系统能不能被工程约束。",
    topics: [
      "12-factor-agents",
      "building-effective-agents",
      "practical-guide-building-ai-agents",
      "react-framework",
      "writing-tools-for-agents",
    ],
  },
  {
    id: "context-engineering",
    label: "上下文工程",
    blurb:
      "从 prompt engineering 扩展到 context 采集、压缩、隔离与 memory 系统——长任务 Agent 的核心约束。",
    topics: [
      "context-engineering",
      "context-engineering-2.0-pdf",
      "build-agent-context-engineering",
      "agent-memory-survey",
    ],
  },
  {
    id: "agent-engineering",
    label: "Agent 工程与生产",
    blurb:
      "评测、可观测性、可靠性、安全与多 Agent 协作——把 demo 推到生产环境要补齐的工程能力。",
    topics: ["agent-engineering", "agent-evaluation-harness", "loop-engineering", "agentic-rl"],
  },
  {
    id: "learning-path",
    label: "学习路径与资料",
    blurb: "学习路线、讲座清单、面试题与外部长文资料。",
    topics: [
      "roadmap",
      "zero-to-hero",
      "interview",
      "nanoGPT",
      "karpathy-2026",
      "agent-cost-optimization",
      "agent-performance-evaluation",
      "ai-native-sdlc",
      "deepseek-harness",
      "harness-engineering",
      "others",
    ],
  },
];

export const FALLBACK_CATEGORY: Category = {
  id: "uncategorized",
  label: "其他",
  blurb: "尚未归入分类映射表的文档。编辑 src/lib/categories.ts 可将其归组。",
  topics: [],
};

/** Human-readable labels for topic directories, used as card eyebrows. */
export const TOPIC_LABELS: Record<string, string> = {
  "12-factor-agents": "12-Factor Agents",
  "agent-cost-optimization": "成本优化",
  "agent-engineering": "Agent Engineering",
  "agent-evaluation-harness": "Evaluation Harness",
  "agent-memory-survey": "Agent Memory",
  "agent-performance-evaluation": "性能评估",
  "agentic-rl": "Agentic RL",
  "ai-native-sdlc": "AI-Native SDLC",
  "build-agent-context-engineering": "Context Engineering",
  "building-effective-agents": "Effective Agents",
  "context-engineering": "Context Engineering",
  "context-engineering-2.0-pdf": "Context Engineering 2.0",
  "deepseek-harness": "DeepSeek Harness",
  embedding: "Embedding",
  gpt: "GPT",
  "harness-engineering": "Harness Engineering",
  interview: "面试",
  "karpathy-2026": "Karpathy 2026",
  "kv-cache": "KV Cache",
  "llm-alignment": "对齐",
  "loop-engineering": "Loop Engineering",
  lora: "LoRA",
  nanoGPT: "nanoGPT",
  others: "长文资料",
  "positional-encoding": "位置编码",
  "practical-guide-building-ai-agents": "OpenAI 实用指南",
  qlora: "QLoRA",
  "react-framework": "ReAct",
  roadmap: "Roadmap",
  sampling: "采样参数",
  tokenization: "Tokenization",
  transformer: "Transformer",
  "writing-tools-for-agents": "Tools for Agents",
  "zero-to-hero": "Zero to Hero",
};

/**
 * Per-document overrides, keyed by `<topic>/<source filename>`.
 *
 * Needed when the Markdown has no `# H1` to derive a title from, when the
 * first paragraph makes a poor card summary, or when the auto-derived slug is
 * unusable — `slugify` drops CJK, so a filename like `Agent经济学.html`
 * collapses to `agent` and can steal that slug from another document.
 */
export const DOC_OVERRIDES: Record<
  string,
  { title?: string; summary?: string; slug?: string }
> = {
  // Starts with a `>` source-attribution blockquote instead of an H1.
  "build-agent-context-engineering/build-agent-context-engineering.md": {
    title: "Agent 架构综述：从 Prompt 到上下文工程构建 AI Agent",
    summary:
      "原文资源本地化，覆盖结构化提示词、上下文工程、RAG、工具函数、Agent 规划与多 Agent 协作。",
  },
  // A flat Q&A list whose H1 is the first question, not a document title.
  "interview/agent-llm-dev.md": {
    title: "AI Agent / LLM 开发岗面试题",
    summary:
      "按题目组织的面试问答，覆盖 Prompt / RAG / 微调 / Workflow / Agent 的选型边界与工程取舍。",
  },
  "nanoGPT/nanoGPT.pdf": {
    title: "nanoGPT",
    summary: "Karpathy nanoGPT 讲解材料（PDF）。",
  },
  "others/企业级AI Agent落地挑战 — 从Demo到Production的鸿沟.pdf": {
    title: "企业级 AI Agent 落地挑战：从 Demo 到 Production 的鸿沟",
    summary: "企业环境下把 Agent demo 推向生产的工程差距与应对方法（PDF）。",
  },
  "others/AI时代的工程师-颠覆困境与进化.pdf": {
    title: "AI 时代的工程师：颠覆、困境与进化",
    summary: "AI 工具冲击下工程师角色的变化与能力演进路径（PDF）。",
  },
  // Both of these slugify to bare "agent" (CJK is dropped). Pin them so the
  // ordering of discovery can't shuffle which one gets the hash suffix.
  "others/长时程自主Agent — 从完成任务到持续经营任务.pdf": {
    slug: "agent",
    title: "长时程自主 Agent：从完成任务到持续经营任务",
    summary: "长周期自主 Agent 的目标维持、状态管理与持续运营视角（PDF）。",
  },
  "others/Agent经济学.html": {
    slug: "agent-economics",
  },
};

/** Resolve which category a topic directory belongs to. */
export function categoryForTopic(topic: string): Category {
  return (
    CATEGORIES.find((category) => category.topics.includes(topic)) ??
    FALLBACK_CATEGORY
  );
}
