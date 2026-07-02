# Karpathy Zero to Hero：讲座列表与学习顺序

资料来源：[Neural Networks: Zero to Hero — Andrej Karpathy](https://karpathy.ai/zero-to-hero.html)

## 讲座列表

| # | 标题 | 时长 | 链接 |
|---:|---|---|---|
| 1 | The spelled-out intro to neural networks and backpropagation: building micrograd | 2h25m | https://youtu.be/VMj-3S1tku0 |
| 2 | The spelled-out intro to language modeling: building makemore | 1h57m | https://youtu.be/PaCmpygFfXo |
| 3 | Building makemore Part 2: MLP | 1h15m | https://youtu.be/TCH_1BHY58I |
| 4 | Building makemore Part 3: Activations & Gradients, BatchNorm | 1h55m | https://youtu.be/P6sfmUTpUmc |
| 5 | Building makemore Part 4: Becoming a Backprop Ninja | 1h55m | https://youtu.be/q8SA3rM6ckI |
| 6 | Building makemore Part 5: Building a WaveNet | 56m | https://youtu.be/t3YJ5hKiMQ0 |
| 7 | Let's build GPT: from scratch, in code, spelled out. | 1h56m | https://www.youtube.com/watch?v=kCc8FmEb1nY |
| 8 | Let's build the GPT Tokenizer | 2h13m | https://youtu.be/zduSFxRajkE |

> 状态：ongoing，第 8 讲后可能继续更新。

## 简介（按页面原样摘录）

**1. The spelled-out intro to neural networks and backpropagation: building micrograd** (2h25m)
The most step-by-step explanation of backpropagation and training of neural networks. Assumes only basic Python and vague recollection of high school calculus.

**2. The spelled-out intro to language modeling: building makemore** (1h57m)
Implements a bigram character-level language model, later complexified into a modern Transformer. Focuses on torch.Tensor and the language modeling framework (training, sampling, negative log likelihood loss).

**3. Building makemore Part 2: MLP** (1h15m)
Implements a multilayer perceptron (MLP) character-level language model. Introduces ML basics: training, learning rate, hyperparameters, evaluation, train/dev/test splits, under/overfitting.

**4. Building makemore Part 3: Activations & Gradients, BatchNorm** (1h55m)
Examines forward pass activations, backward pass gradients, and pitfalls of improper scaling. Introduces Batch Normalization. Residual connections and Adam are noted as todos for later.

**5. Building makemore Part 4: Becoming a Backprop Ninja** (1h55m)
Backpropagates manually through the 2-layer MLP without loss.backward(), through cross entropy, linear, tanh, batchnorm, and embedding layers, building intuition for gradients over tensors.

**6. Building makemore Part 5: Building a WaveNet** (56m)
Makes the 2-layer MLP deeper with a tree-like structure, arriving at a WaveNet-like architecture. Provides familiarity with torch.nn and a typical deep learning development process.

**7. Let's build GPT: from scratch, in code, spelled out.** (1h56m)
Builds a GPT following "Attention is All You Need" and OpenAI's GPT-2/GPT-3. Recommends watching earlier makemore videos first for the autoregressive framework and PyTorch nn basics.

**8. Let's build the GPT Tokenizer** (2h13m)
Builds the GPT Tokenizer from scratch, covering Byte Pair Encoding, encode/decode functions, and how many LLM issues trace back to tokenization.

## 代码仓库

- [karpathy/micrograd](https://github.com/karpathy/micrograd) — 第 1 讲
- [karpathy/makemore](https://github.com/karpathy/makemore) — 第 2-6 讲
- [karpathy/ng-video-lecture](https://github.com/karpathy/ng-video-lecture) — 第 7 讲
- [karpathy/minbpe](https://github.com/karpathy/minbpe) — 第 8 讲
- [karpathy/nn-zero-to-hero-notes](https://github.com/karpathy/nn-zero-to-hero-notes) — 官方笔记

## 学习顺序

按 1 → 8 顺序。每讲都假设你看过前面所有讲。

- 第 7 讲（Let's build GPT）页面明确建议"先看前面 makemore 视频"，跳过前置会影响第 7 讲的理解。
- 第 8 讲（Tokenizer）和前面 7 讲内容独立，可以放在第 7 讲之前或之后。
