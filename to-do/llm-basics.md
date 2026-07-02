---
title: 大模型基础 · 外链沉淀待办
status: pending
owner: 用户主导
created: 2026-07-02
---

# 大模型基础 · 外链沉淀待办

> 目标：将开发岗面试必问的大模型基础知识，按主题沉淀到 `docs/<topic>/`，每个主题一个独立目录、英文文件名、引用原文图片资源，每篇文档采用 writing-skill 标准结构。
> 节奏：**用户主导**，每完成一项将 `pending` 改为 `done` 并标注完成日期。

## 沉淀范围

### ✅ 本轮沉淀（9 个主题）

| # | 面试问题 | 主外链 | 状态 |
|---|---|---|---|
| Q1 | Transformer Self-Attention 怎么算？Q/K/V 是什么？ | [The Illustrated Transformer](https://jalammar.github.io/illustrated-transformer/) | done |
| Q2 | GPT vs BERT 区别？为什么 LLM 用 Decoder-Only？ | [The Illustrated GPT-2](https://jalammar.github.io/illustrated-gpt2/) | done |
| Q3 | Tokenization 是什么？BPE / WordPiece / Unigram 区别？ | [Hugging Face Tokenizer Summary](https://huggingface.co/docs/transformers/tokenizer_summary) | done |
| Q4 | 主流大模型用的什么位置编码？（RoPE） | [RoFormer 论文图 1](https://arxiv.org/abs/2104.09864) | done |
| Q5 | 推理时 sampling 参数（temperature / top_p / top_k） | [HF: How to generate text](https://huggingface.co/blog/how-to-generate) | done |
| Q6 | KV Cache 是什么？为什么能加速推理？ | [Unfolding LLMs Math: KV Cache](https://huggingface.co/blog/unfolding-llm-math) | done |
| Q7 | LoRA 是什么？为什么能低资源微调？ | [LoRA 论文图 1](https://arxiv.org/abs/2106.09685) | done |
| Q8 | QLoRA 是什么？和 LoRA 区别？ | [QLoRA 论文](https://arxiv.org/abs/2305.14314) | done |
| Q12 | Embedding 模型怎么选？ | [MTEB Leaderboard](https://huggingface.co/spaces/mteb/leaderboard) | done |

### ⏸️ 暂不沉淀（3 个主题）

| # | 面试问题 | 主外链 | 状态 |
|---|---|---|---|
| Q9 | SFT / RLHF / DPO 区别？ | [Illustrated DPO](https://huggingface.co/blog/dpo-trl) | deferred |
| Q10 | INT8 / INT4 / GPTQ / AWQ 量化区别？ | [HF Quantization 概览](https://huggingface.co/docs/transformers/quantization) | deferred |
| Q11 | 推理服务框架怎么选？（vLLM / TGI / llama.cpp） | vLLM 论文 + llama.cpp | deferred |

> 后续视进度再启动 Q9-Q11 沉淀。

---

## 沉淀目标结构

按主题每个独立目录，目录与文件名一律使用英文小写连字符：

```
docs/
├── transformer/                          (Q1)
│   ├── 01-transformer-self-attention.md
│   └── figures/                          # 原文图片本地化
├── gpt/                                  (Q2)
│   ├── 01-decoder-only-vs-encoder-decoder.md
│   └── figures/
├── tokenization/                         (Q3)
│   ├── 01-bpe-wordpiece-unigram.md
│   └── figures/
├── positional-encoding/                  (Q4)
│   ├── 01-rope-relative-position.md
│   └── figures/
├── sampling/                             (Q5)
│   └── 01-temperature-top-p-top-k.md
├── kv-cache/                             (Q6)
│   └── 01-kv-cache-inference.md
├── lora/                                 (Q7)
│   └── 01-lora-low-rank-adaptation.md
├── qlora/                                (Q8)
│   └── 01-qlora-quantized-lora.md
└── embedding/                            (Q12)
    └── 01-embedding-model-selection.md
```

约定：

- 目录名用主题英文短名，不放中文。
- 文档名用 `NN-主题-短描述.md` 形式，数字用于控制同主题多篇的顺序。
- 原文插图下载到该主题目录的 `figures/` 子目录，文档用相对路径引用。

---

## 单篇沉淀模板（writing-skill 标准）

每篇文档采用以下结构：

1. **标题**
2. **来源 / 延伸阅读**（外链清单）
3. **阅读目标 / 核心结论**（一句话）
4. **术语表**（必要时）
5. **背景与问题**（为什么问这个）
6. **结构化主体**（带编号小节）
7. **对比表 / 清单**（必要时）
8. **工程要点与实现检查**
9. **关键结论**
10. **面试速答卡**（Q&A 形式，3-5 条）

---

## 沉淀节奏（由用户决定）

> 约定：用户每次发"开始沉淀 Qx"，我按模板输出对应文档到 `docs/<topic>/`；同时更新本文件的 `pending → done` 状态与完成日期。

可选节奏：

- **逐个沉淀**：Q1 → Q2 → Q3 → ... 适合深度打磨
- **分批沉淀**：架构组（Q1+Q2+Q4）→ 推理组（Q5+Q6）→ 微调组（Q7+Q8）→ 选型组（Q12）适合按主题成系列
- **混合节奏**：先快后慢，先沉淀 1-2 篇定下模板风格，再批量推进

用户随时可：

- 调整模板结构
- 增减某篇的章节
- 改写某篇的侧重点（如 Q5 偏工程 vs 偏原理）
- 插入额外的内链（与 `docs/` 已有文档关联）

---

## 沉淀进度追踪

| # | 主题 | 状态 | 完成日期 | 备注 |
|---|---|---|---|---|
| Q1 | Transformer Self-Attention | done | 2026-07-02 | 已沉淀到 `docs/transformer/01-transformer-self-attention.md` |
| Q2 | Decoder-Only 与 GPT | done | 2026-07-02 | 已沉淀到 `docs/gpt/01-decoder-only-vs-encoder-decoder.md` |
| Q3 | Tokenization | done | 2026-07-02 | 已沉淀到 `docs/tokenization/01-bpe-wordpiece-unigram.md` |
| Q4 | RoPE 位置编码 | done | 2026-07-02 | 已沉淀到 `docs/positional-encoding/01-rope-relative-position.md` |
| Q5 | 推理采样参数 | done | 2026-07-02 | 已沉淀到 `docs/sampling/01-temperature-top-p-top-k.md` |
| Q6 | KV Cache | done | 2026-07-02 | 已沉淀到 `docs/kv-cache/01-kv-cache-inference.md` |
| Q7 | LoRA | done | 2026-07-02 | 已沉淀到 `docs/lora/01-lora-low-rank-adaptation.md` |
| Q8 | QLoRA | done | 2026-07-02 | 已沉淀到 `docs/qlora/01-qlora-quantized-lora.md` |
| Q12 | Embedding 选型 | done | 2026-07-02 | 已沉淀到 `docs/embedding/01-embedding-model-selection.md` |

---

## 学习路径沉淀（独立于 9 个 Q）

| # | 资源 | 状态 | 完成日期 | 备注 |
|---|---|---|---|---|
| L1 | Karpathy "Neural Networks: Zero to Hero" | done | 2026-07-02 | 已沉淀到 `docs/zero-to-hero/01-karpathy-zero-to-hero-learning-path.md` |

---

## 附：参考来源汇总

外部参考资源（按主题）：

- **Q1/Q2**: [The Illustrated Transformer](https://jalammar.github.io/illustrated-transformer/) · [The Illustrated GPT-2](https://jalammar.github.io/illustrated-gpt2/)
- **Q3**: [HF Tokenizer Summary](https://huggingface.co/docs/transformers/tokenizer_summary) · [tiktoken](https://github.com/openai/tiktoken) · [SentencePiece](https://github.com/google/sentencepiece)
- **Q4**: [RoFormer 论文](https://arxiv.org/abs/2104.09864) · [GQA 论文](https://arxiv.org/abs/2305.13245)
- **Q5**: [HF How to generate](https://huggingface.co/blog/how-to-generate) · [Speculative Decoding](https://arxiv.org/abs/2211.17192)
- **Q6**: [HF Unfolding LLMs Math](https://huggingface.co/blog/unfolding-llm-math) · [vLLM 论文 PagedAttention](https://arxiv.org/abs/2309.06180)
- **Q7**: [LoRA 论文](https://arxiv.org/abs/2106.09685) · [PEFT 库](https://huggingface.co/docs/peft)
- **Q8**: [QLoRA 论文](https://arxiv.org/abs/2305.14314) · [bitsandbytes](https://github.com/TimDettmers/bitsandbytes)
- **Q12**: [MTEB Leaderboard](https://huggingface.co/spaces/mteb/leaderboard) · [Sentence-Transformers](https://www.sbert.net/)

内部参考文档：

- `/opt/workspace/ai-agent-interview-guide/docs/01-面试八股文/07-大模型基础.md`（B1 主参考）
- `/opt/workspace/ai-agents-from-zero/1-1-大模型认知与工程概览.md`
- `/opt/workspace/ai-agents-from-zero/1-2-提示词工程基础.md`
- `/opt/workspace/ai-agents-from-zero/28-大模型微调概述与整体流程.md`
