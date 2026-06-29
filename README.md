# Learn AI Agent

一个面向 AI Agent 工程实践的中文知识库，聚焦 agent 设计原则、上下文工程、工程化落地和可复用写作规范。

## 项目定位

本仓库用于沉淀 AI Agent 相关的系统化学习文档。内容不是资料摘抄，而是以工程实践为导向，对论文、开源项目和技术文章进行结构化整理，形成可阅读、可复盘、可继续扩展的中文文档。

当前内容重点包括：

| 主题 | 文档 | 说明 |
|---|---|---|
| 12-Factor Agents | [12-Factor Agents 设计原则](docs/12-factor-agents/12-factor-agents-principles.md) | 基于 `humanlayer/12-factor-agents` 的设计原则整理，包含名词解释、背景、12 条原则拆解和生产落地检查表。 |
| Context Engineering 2.0 | [Context Engineering 2.0](docs/context-engineering-2.0-pdf/context_engineering_2_cn_notes.md) | 基于论文 `Context Engineering 2.0` 的中文整理，包含核心结论、关键名词、阶段框架和工程启发。 |

## 内容组织

```text
learn-ai-agent/
├── README.md
├── index.md
├── _config.yml
├── .github/workflows/pages.yml
├── docs/
│   ├── 12-factor-agents/
│   │   ├── 12-factor-agents-principles.md
│   │   └── figures/
│   └── context-engineering-2.0-pdf/
│       ├── context_engineering_2_cn_notes.md
│       └── context_engineering_2_figures/
└── agents/
    └── writing-skill/
        ├── SKILL.md
        └── references/style-guide.md
```

每篇主题文档独立放在一个目录中，图片资源放在同级 `figures/` 或主题专属图片目录中，Markdown 使用相对路径引用本地图片，避免依赖外部图片链接。

## 写作规范

本仓库提供了项目级写作 skill：

[agents/writing-skill/SKILL.md](agents/writing-skill/SKILL.md)

后续让 agent 编写或修改文档时，应先读取该 skill，并按 [style-guide.md](agents/writing-skill/references/style-guide.md) 中的风格约定输出。核心要求包括：

- 默认使用中文，保持客观、工程化、可执行的表达。
- 优先使用清晰章节、表格、检查表和简短代码片段。
- 学习型文档不使用“学习笔记”这类标题标签。
- 图片必须本地化保存，并用相对路径引用。
- 术语解释表使用 `名词 / 解释 / 简单例子` 三列表头。

## GitHub Pages

仓库已内置 GitHub Pages 配置：

- `_config.yml`：Jekyll 站点基础配置。
- `index.md`：站点首页。
- `.github/workflows/pages.yml`：通过 GitHub Actions 构建并发布 Pages。

启用方式：

1. 将仓库推送到 GitHub，仓库名建议保持为 `learn-ai-agent`。
2. 在 GitHub 仓库 `Settings -> Pages` 中选择 `GitHub Actions` 作为发布来源。
3. 推送 `main` 分支后，workflow 会自动构建并发布站点。

发布后访问地址通常为：

```text
https://<github-user>.github.io/learn-ai-agent/
```

## 本地预览

如果只阅读 Markdown，可以直接在编辑器中打开文档。

如需本地预览 GitHub Pages 效果，可使用 Jekyll：

```bash
bundle exec jekyll serve
```

如果本机没有 Ruby/Jekyll 环境，也可以直接依赖 GitHub Actions 构建发布。

## 维护原则

- 新主题使用独立目录，避免把不同资料混在同一层级。
- 引用外部资料时保留来源链接。
- 长文档先给核心结论，再展开背景、概念、框架和落地检查项。
- 图片、图表、截图等资源放入主题目录内，不使用远程图片作为正文依赖。
- 新增文档前先参考 `agents/writing-skill`，保持仓库整体风格一致。
