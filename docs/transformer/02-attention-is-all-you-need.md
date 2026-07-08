# Attention Is All You Need：Transformer 与纯注意力架构

> 论文链接：https://arxiv.org/abs/1706.03762  

## 核心结论

《Attention Is All You Need》提出 Transformer：第一个完全基于注意力机制、不依赖循环和卷积的序列转换模型。它在 WMT 2014 英德翻译上拿到 28.4 BLEU，超过当时所有模型（含集成模型）2 个 BLEU 以上；在英法翻译上拿到 41.8 BLEU，训练成本不到此前 SOTA 的四分之一。Base 模型 8 张 P100 训练 12 小时，Big 模型 3.5 天。

Transformer 的工程意义不在翻译分数本身，而在它把序列建模从“按时间步串行”改成“一次性全并行”。这一改动解决了 RNN 训练时无法并行、长距离依赖路径过长两个结构性问题，成为后来 BERT、GPT 乃至所有现代 LLM 的共同底座。

本文档面向工程读者，重点拆解三件事：注意力机制为什么能取代循环、Multi-Head 与位置编码各自补上了什么短板、以及论文里的训练配方在今天的工程实践中还剩多少参考价值。

## 名词解释

| 名词 | 解释 | 简单例子 |
|---|---|---|
| Sequence Transduction | 把一个序列映射成另一个序列的任务统称，机器翻译、摘要、语音识别都属于此类。 | 输入“今天天气不错”输出“nice weather today”。 |
| Encoder-Decoder | 编码器把输入序列压成连续表示，解码器基于该表示自回归地生成输出。 | 翻译时 Encoder 读完整句中文，Decoder 逐词生成英文。 |
| Self-Attention | 同一序列内部 token 之间互相计算相关性并交换信息，每个位置都能直接看到所有位置。 | “it”能直接关联到前文的“animal”，不必逐层传递。 |
| Scaled Dot-Product Attention | Transformer 用的注意力算子：`softmax(QK^T / sqrt(d_k)) V`，缩放因子稳定梯度。 | d_k=64 时点积方差为 64，不缩放会让 softmax 趋向 one-hot。 |
| Multi-Head Attention | 把 d_model 维拆成 h 个子空间，每头独立做 attention 后 concat 再投影，让模型在不同子空间关注不同关系。 | 一头看指代、一头看句法、一头看局部搭配。 |
| Masked Self-Attention | Decoder 自注意力中遮住未来位置，保证位置 t 看不到 t 之后的内容，维持自回归性质。 | 预测第 5 个词时不许看到第 6、7 个词。 |
| Cross-Attention | 注意力的 Q 来自一侧（Decoder），K/V 来自另一侧（Encoder 输出），用于让解码端检索编码端信息。 | Decoder 生成英文词时，用 Q 去 Encoder 的中文表示里取相关内容。 |
| Position-wise FFN | 对序列每个位置独立施加同一个两层全连接（中间 ReLU），等价于 kernel size 为 1 的两层卷积。 | 每个位置的 512 维向量先升到 2048 维再降回 512 维。 |
| Positional Encoding | 给 token embedding 注入位置信息，因为纯 self-attention 对顺序不敏感。 | 把“第 3 个位置”编码成一个固定向量加到 embedding 上。 |
| d_model | 模型内部所有子层和 embedding 的统一维度，Base 为 512，Big 为 1024。 | Base 模型里每个 token 用 512 维向量表示。 |
| LayerNorm + Residual | 每个子层都套 `LayerNorm(x + Sublayer(x))`，残差连接缓解深网络退化，LayerNorm 稳定分布。 | 6 层堆叠没有残差会难以训练。 |
| Label Smoothing | 训练时把 one-hot 标签软化成 ε 分布，降低模型对单一输出的自信度。 | ε_ls=0.1 时目标分布从 [0,1] 变成 [0.05, 0.9, ...]。 |
| Warmup | 学习率先线性升温再平方根衰减，配合 Adam 让深层注意力模型训练稳定。 | 前 4000 步线性升到峰值，之后缓慢下降。 |

## 1. 背景：循环与卷积为何不够

论文出发点是当时序列建模的主流是 RNN（含 LSTM、GRU）和 CNN。RNN 的两个结构性缺陷是 Transformer 要解决的核心问题：

1. **无法并行**。RNN 沿时间步推进，h_t 必须等 h_{t-1} 算完才能开始，序列越长 GPU 利用率越低，训练时间随序列长度线性堆积。
2. **长距离依赖路径长**。要把位置 t 和 t+k 的信息联系起来，RNN 需要走 k 步，信号在反复传递中容易衰减或被噪声覆盖；CNN 虽然每层并行，但要靠多层堆叠扩大感受野，最长路径是 O(log_k(n))。

Transformer 的选择是用 self-attention 把任意两个位置之间的距离压成 O(1)：每个位置直接和所有位置算一次相似度。代价是每层计算量从 RNN 的 O(n·d²) 变成 O(n²·d)，但换来的是全并行和短路径。当序列长度 n 小于表示维度 d（这是 BPE/word-piece 下的常见情况）时，self-attention 在计算量上也更划算。

| 维度 | RNN | CNN | Self-Attention |
|---|---|---|---|
| 每层复杂度 | O(n·d²) | O(k·n·d²) | O(n²·d) |
| 串行操作数 | O(n) | O(1) | O(1) |
| 最长依赖路径 | O(n) | O(log_k(n)) | O(1) |
| 是否可并行 | 否 | 是 | 是 |
| 长序列成本 | 线性增长 | 线性增长 | 平方增长 |

这张表是论文 Table 1 的工程化版本，也是后来所有注意力变体（sparse attention、linear attention、FlashAttention）要权衡的同一个轴：拿 O(n²) 换并行和短路径，在短序列上赚、在长序列上亏。

## 2. 整体架构：Encoder-Decoder 与残差栈

Transformer 采用 Encoder-Decoder 结构。Encoder 把输入符号序列 (x_1,...,x_n) 映射成连续表示 z = (z_1,...,z_n)；Decoder 自回归地生成输出 (y_1,...,y_m)，每一步把之前生成的输出作为输入。

两侧各 N=6 层堆叠，每层内部都围绕子层（sub-layer）组织，每个子层统一套用残差连接加 LayerNorm：

```
output = LayerNorm(x + Sublayer(x))
```

为了支持残差相加，所有子层和 embedding 的输出维度都固定为 d_model（Base 为 512）。

### 2.1 Encoder

每层两个子层：

1. Multi-Head Self-Attention。
2. Position-wise Feed-Forward。

Encoder 的 self-attention 是双向的，每个位置能看到整个输入序列，适合做“理解”。

### 2.2 Decoder

每层三个子层：

1. **Masked Multi-Head Self-Attention**：遮住未来位置，保证自回归。
2. **Encoder-Decoder Cross-Attention**：Q 来自 Decoder 上一层输出，K/V 来自 Encoder 顶层输出，让解码端检索编码端信息。
3. Position-wise Feed-Forward。

Decoder 的自注意力是单向的，这是后来 GPT 走 Decoder-Only 路线时保留的关键约束。

| 子层 | 出现位置 | 注意力类型 | Q / K / V 来源 | 作用 |
|---|---|---|---|---|
| Self-Attention | Encoder 每层 | 双向 | 均来自上一层 Encoder | 输入序列内部交换信息 |
| Masked Self-Attention | Decoder 每层 | 单向 | 均来自上一层 Decoder | 输出序列内部交换信息，禁止看未来 |
| Cross-Attention | Decoder 每层 | — | Q 来自 Decoder，K/V 来自 Encoder | 解码端检索编码端表示 |
| FFN | 两侧每层 | — | 单独作用于每个位置 | 非线性变换与特征再混合 |

## 3. Scaled Dot-Product Attention

注意力机制的核心算子：

```
Attention(Q, K, V) = softmax(QK^T / sqrt(d_k)) V
```

执行步骤：Q 与所有 K 做点积得到相似度，除以 sqrt(d_k) 缩放，softmax 归一化成权重，再用权重对 V 加权求和。

**为什么要除以 sqrt(d_k)**。假设 Q、K 的分量均值 0、方差 1，点积 q·k 的方差为 d_k。d_k 越大，点积绝对值越大，softmax 输出会被推向接近 one-hot 的区域，那里的梯度趋近于零，训练停滞。除以 sqrt(d_k) 把方差压回 1，让 softmax 保持在梯度敏感的区间。

论文同时比较了两种注意力实现：

| 维度 | Dot-Product（缩放后） | Additive（加性） |
|---|---|---|
| 计算 | 矩阵乘法 | 逐元素相加后过 MLP |
| 速度 | 快，可用高度优化的矩阵乘 | 慢 |
| 精度 | d_k 小时两者接近；d_k 大时不缩放会变差 | 对大 d_k 更稳定 |

论文选择缩放点积，是因为它能在 d_k 较大时保持精度，同时享受矩阵乘法的硬件加速。这一选择直接决定了后来所有注意力实现都建立在 QK^T 这个矩阵乘上。

## 4. Multi-Head Attention

单次 attention 只能学一种相关性模式。Multi-Head 把 Q/K/V 用不同投影矩阵线性映射 h 次，每头独立做 attention，再 concat 后投影回 d_model：

```
MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O
head_i = Attention(Q W_i^Q, K W_i^K, V W_i^V)
```

参数维度：W_i^Q, W_i^K ∈ R^(d_model × d_k)，W_i^V ∈ R^(d_model × d_v)，W^O ∈ R^(h·d_v × d_model)。

Base 配置：h=8，d_k = d_v = d_model/h = 64。每头维度降到 64，8 头拼起来正好 512，回到 d_model。

**工程含义**。Multi-Head 的总计算量和单头全维 attention 接近，但把表示拆到多个子空间，让模型在“同一层”里同时关注不同类型的关系：一头可能负责指代消解，一头负责句法依存，一头负责局部搭配。论文 Table 3 的消融显示，head 数过少或过多都会掉点：太少表达力不足，太多每头维度过低、信息不够。

| 维度 | 单头全维 | Multi-Head（h=8） |
|---|---|---|
| 总参数量 | 3 个 d_model×d_model 投影 | 8 组 d_model×64 投影，总量相当 |
| 总 FLOPs | 接近 | 接近 |
| 可建模的关系类型 | 单一 | 多种并行 |
| 单头维度 | 512 | 64 |

## 5. 注意力的三种用法

论文在同一套 Multi-Head 算子上定义了三种用法，区别只在 Q/K/V 的来源：

1. **Encoder-Decoder Attention**：Q 来自 Decoder 上一层，K/V 来自 Encoder 顶层输出。这是 Decoder 检索输入信息的唯一通道。
2. **Encoder Self-Attention**：Q/K/V 全部来自上一层 Encoder，双向。
3. **Decoder Self-Attention**：Q/K/V 全部来自上一层 Decoder，但用 mask 遮住未来位置（在 softmax 前把对应分数设为 −∞），保证位置 t 只能看到 t 及之前。

这种“同一算子、不同接线”的设计是 Transformer 工程上的关键抽象：注意力本身是一个通用检索原语，Encoder/Decoder 的差异只体现在谁做查询、谁被查询、要不要遮未来。后来 BERT 只取 Encoder 自注意力、GPT 只取 Decoder 带掩码自注意力，都是对这套接线的子集选择。

## 6. Position-wise Feed-Forward Network

每个位置独立施加同一个两层全连接，中间 ReLU：

```
FFN(x) = max(0, x W_1 + b_1) W_2 + b_2
```

Base 配置：输入输出维度 d_model = 512，中间层 d_ff = 2048，即先升维 4 倍再降回来。不同层用不同参数。

**工程含义**。FFN 等价于 kernel size 为 1 的两层卷积，作用在序列每个位置上，不跨位置混合信息（跨位置的工作已经由 attention 做完）。它的角色更接近“逐位置的非线性特征变换”和“容量瓶颈调节器”：d_ff/d_model 的比值（论文取 4）直接控制每层可表达的非线性复杂度，是模型容量和参数量的重要旋钮。现代实现里 FFN 占参数量的大头，这也是 SwiGLU、MoE 等改进都聚焦在 FFN 上的原因。

## 7. Embedding 与 Softmax 权重共享

论文用学习的 embedding 把 token 映射到 d_model 维向量。两个工程细节：

1. **三处共享权重**：Encoder 输入 embedding、Decoder 输入 embedding、Decoder 输出 softmax 前的线性变换，共用同一个 d_model × vocab 矩阵。这能显著减少参数量，也让 token 的输入表示和输出 logits 对齐。
2. **embedding 乘 sqrt(d_model)**：补偿 embedding 初始化方差偏小、和位置编码相加后被稀释的问题，让两者在同一量级。

权重共享是后来 GPT、BERT 都沿用的做法，是减少大词表参数量的关键工程手段。

## 8. 位置编码：Sinusoidal

Self-Attention 本身对位置完全不变——打乱输入顺序，attention 分布不变。因此必须显式注入位置信息。论文用固定的正余弦编码：

```
PE(pos, 2i)   = sin(pos / 10000^(2i/d_model))
PE(pos, 2i+1) = cos(pos / 10000^(2i/d_model))
```

把 PE 加到 token embedding 上，随模型一起训练但不学习（PE 是常量）。

**为什么选正余弦**。波长从 2π 到 10000·2π 成几何级数，不同维度对应不同尺度的位置周期。关键性质是 `PE(pos+k)` 可以表示为 `PE(pos)` 的线性函数，这意味着模型理论上能从绝对位置编码里学到相对位置关系。

**外推考量**。论文也实验了可学习的位置编码，结果与正余弦几乎相同。选正余弦是因为它可能外推到比训练时更长的序列——这是论文为后续长度外推研究留下的伏笔，后来的 ALiBi、RoPE 都在解决同一个问题。

| 位置编码类型 | 是否学习 | 外推能力 | 后续用途 |
|---|---|---|---|
| Sinusoidal（本文） | 否，固定 | 理论可外推 | 原始 Transformer |
| Learned | 是 | 不可外推 | GPT-2、BERT 早期 |
| RoPE | 是（旋转角度固定） | 配合 NTK/YaRN 可外推 | 主流 LLM |
| ALiBi | 否 | 可外推 | 部分模型 |

## 9. 为什么用 Self-Attention：复杂度与路径

论文用 Table 1 论证 self-attention 的优势，核心是三条同时改善：

1. 每层复杂度 O(n²·d)，在 n < d 时优于 RNN 的 O(n·d²)。
2. 串行操作数 O(1)，全并行，训练快。
3. 最长依赖路径 O(1)，任意两位置直接相连，利于长距离依赖。

受限自注意力（restricted，每个位置只看半径 r 内）把复杂度降到 O(r·n·d)，但路径变回 O(n/r)，是长序列场景下的折中方案，论文把它列为未来工作。

这一节的价值在于它把架构选择和可计算的复杂度绑定，给后续工作提供了同一套比较框架：任何新注意力变体都要回答“复杂度、并行度、路径长度”三个问题。

## 10. 训练细节

### 10.1 数据与批大小

- 英德：WMT 2014，约 450 万句对，BPE 词表约 37K。
- 英法：WMT 2014，3600 万句，word-piece 词表 32K。
- 每个 batch 约 25K 源 token + 25K 目标 token，按 token 数而非句数组批，让 GPU 利用率稳定。

### 10.2 硬件与时长

8 张 NVIDIA P100。Base 模型 0.4s/step、100K 步、12 小时；Big 模型 1.0s/step、300K 步、3.5 天。对比当时 RNN 模型动辄数周的训练周期，这是Transformer 并行性的直接证据。

### 10.3 优化器与学习率

Adam（β1=0.9, β2=0.98, ε=1e-9），学习率采用 warmup 后平方根衰减：

```
lr = d_model^(-0.5) * min(step^(-0.5), step * warmup^(-1.5))
```

前 4000 步线性升温，之后按步数平方根倒数衰减。峰值学习率随 d_model 增大而降低（d_model^(-0.5)），这是为什么大模型要配更小学习率的一个来源。这套 warmup 配方在 BERT、GPT 里基本沿用，是深层注意力模型训练稳定的经验起点。

### 10.4 正则化

| 手段 | 配置 | 作用位置 | 工程含义 |
|---|---|---|---|
| Residual Dropout | P=0.1（Base）/0.3（Big） | 每个子层输出加到残差前；embedding + PE | 防止过拟合，Big 模型更强正则 |
| Label Smoothing | ε_ls=0.1 | 输出 softmax | 牺牲一点 perplexity，换 BLEU 提升 |

论文特别指出 label smoothing 会损害 perplexity 但提升 accuracy/BLEU——这是一个值得记住的工程教训：**优化指标和评测指标不是一回事**，训练时该优化哪个，取决于下游评测看什么。

### 10.5 模型规模

| 配置 | N | d_model | d_ff | h | d_k | P_drop | 参数量 | 步数 |
|---|---|---|---|---|---|---|---|---|
| Base | 6 | 512 | 2048 | 8 | 64 | 0.1 | ~65M | 100K |
| Big | 6 | 1024 | 4096 | 16 | 64 | 0.3 | ~213M | 300K |

注意 d_k 在 Big 里仍是 64（不是 d_model/h=64 巧合一致），增大的是层数维度和头数。

## 11. 结果

### 11.1 机器翻译（WMT 2014）

| 模型 | EN-DE BLEU | EN-FR BLEU | 训练 FLOPs |
|---|---|---|---|
| Transformer (base) | 27.3 | 38.1 | 3.3×10^18 |
| Transformer (big) | 28.4 | 41.8 | 2.3×10^19 |
| 此前最佳（含集成） | 26.36 | 41.29 | 1.2×10^21 |

Big 模型在英德上超过所有此前模型（含集成）2 个 BLEU 以上；英法训练成本不到此前 SOTA 的 1/4。

推理用 beam search：beam size 4，长度惩罚 α=0.6，最大输出长度 = 输入长度 + 50。Base 平均最后 5 个 checkpoint，Big 平均最后 20 个——checkpoint 平均是当时提升稳定性的常用手段。

### 11.2 消融实验要点（Table 3）

- 单头注意力比最佳配置低 0.9 BLEU；头太多也会掉点。
- 减小 d_k 会损害质量，暗示更复杂的 compatibility function 可能有帮助。
- 更大模型更好；dropout 对防过拟合非常有效。
- 正余弦与可学习位置编码结果几乎相同。

### 11.3 英语句法分析

论文用 4 层 Transformer（d_model=1024）在 WSJ（约 4 万句）上训练：

- 仅 WSJ：91.3 F1（Section 23）。
- 半监督：92.7 F1。

即使不做任务特定调优、只用 WSJ 训练，也超过 BerkeleyParser。这一结果说明 Transformer 的架构具备跨任务泛化能力，不只是翻译专用——这是它成为通用底座的早期信号。

## 12. 工程启发与实现检查

从工程视角，这篇论文留下的不只是“Transformer 这个结构”，而是几条至今仍在生效的设计判断：

1. **并行性是架构级收益**。RNN 的串行不是实现问题而是模型问题，Transformer 通过把时间维上的依赖改成集合上的全连接，让训练时间从“周”降到“天”。后来 LLM 能训到这么大规模，前提就是这一层并行性。
2. **注意力是通用检索原语**。同一算子通过改 Q/K/V 接线就能做 Encoder 自注意力、Decoder 掩码自注意力、Cross-attention。这种正交设计让架构可组合，BERT 和 GPT 都是它的子集。
3. **复杂度框架要绑定可计算量**。论文用复杂度、串行操作数、路径长度三个量论证设计，给后续 sparse/linear/flash 注意力提供了同一把尺子。
4. **训练配方有传承价值**。warmup + sqrt 衰减、label smoothing、dropout 配置、embedding 权重共享、LayerNorm + 残差，这些组件在八年后的模型里依然能认出来，是工程上的稳定选择。
5. **优化指标 ≠ 评测指标**。label smoothing 损害 perplexity 但提升 BLEU，提示训练目标要和下游评测对齐。

落地实现时的检查清单：

| 维度 | 检查项 | 期望状态 |
|---|---|---|
| 缩放 | QK^T 是否除以 sqrt(d_k) | 是，否则大 d_k 下 softmax 饱和、梯度消失 |
| 掩码 | Decoder 自注意力是否在 softmax 前遮未来 | 是，设为 −∞ |
| 残差 | 每个子层是否套 LayerNorm(x + Sublayer(x)) | 是，且输出维度恒为 d_model |
| Multi-Head | h·d_k 是否拼回 d_model | 是，参数总量与单头全维相当 |
| 位置编码 | 是否注入顺序信息 | 是，否则对顺序不变 |
| 权重共享 | 输入/输出 embedding 是否共用 | 视实现而定，大词表下推荐共享 |
| Warmup | 是否有线性升温 | 是，深层注意力模型训练稳定的关键 |
| 评测对齐 | 训练目标是否对齐下游指标 | 是，必要时用 label smoothing 等 |

## 关键结论

Transformer 的核心贡献是用注意力机制同时解决了 RNN 的并行性问题和长距离依赖问题，并把序列建模统一到“集合上的全连接”这一范式。论文里的每一项设计——缩放点积、Multi-Head、残差加 LayerNorm、正余弦位置编码、warmup 配方、权重共享——都不是孤立的技巧，而是围绕“可并行、可堆叠、可外推、训练稳定”这一组工程目标做的协同取舍。

对今天读这篇论文的工程读者，最有价值的不是复述结构图，而是建立两个长期判断：第一，架构选择要和可计算的复杂度绑定，任何注意力变体都要回答复杂度、并行度、路径长度三个问题；第二，训练配方里的 warmup、缩放、残差、权重共享是经得起规模检验的基础设施，理解它们的动机比记住超参更重要。

这篇论文后续的延伸阅读可参考本仓库的 [Transformer Self-Attention：Q/K/V 与注意力怎么算](./01-transformer-self-attention.md)、[KV Cache：自回归推理的工程加速](../kv-cache/01-kv-cache-inference.md)、[RoPE：旋转位置编码与相对注意力](../positional-encoding/01-rope-relative-position.md)。
