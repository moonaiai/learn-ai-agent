# 文档站（web/）

把仓库 `docs/` 下的 Markdown 与 PDF 渲染成静态文档站，部署到 GitHub Pages：
<https://moonaiai.github.io/learn-ai-agent/>

技术栈：Next.js App Router + `output: "export"`（纯静态导出），手写 CSS + design tokens，无运行时数据获取。

## 本地开发

```bash
cd web
npm install
npm run dev        # http://localhost:3000（predev 会自动跑 extract）
```

```bash
npm run extract    # 只重新提取内容，不启服务
npm run typecheck  # tsc --noEmit
npm run build      # prebuild 跑 extract，然后 next build → out/
```

验证 GitHub Pages 的子路径部署（最容易出问题的一环）：

```bash
NEXT_BASE_PATH=/learn-ai-agent npm run build
# 把 out/ 放到一个名为 learn-ai-agent 的目录下再起静态服务，模拟 project site
mkdir -p /tmp/bp && cp -R out /tmp/bp/learn-ai-agent
cd /tmp/bp && python3 -m http.server 4477
# 访问 http://localhost:4477/learn-ai-agent/
```

CI 会断言 `out/` 里不存在缺少 basePath 前缀的 `/doc-assets` 或 `/doc-pdf` 链接。

## 内容从哪来

`scripts/extract-docs.ts` 在构建期递归扫描仓库根的 `docs/`，产出两份 JSON 到
`src/data/generated/`（构建产物，不入库）：

- `docs.json` —— 含渲染后的 HTML，供文档页
- `nav.json` —— 去掉 HTML 的轻量索引，供首页与上下篇导航

同时把图片资源拷到 `public/doc-assets/<主题>/<原子目录名>/`、PDF 拷到
`public/doc-pdf/<主题>/<slug>.pdf`。

**新增一篇文档不需要改任何代码**：把 `.md` 或 `.pdf` 放进 `docs/<主题>/` 即可，
下次构建自动出现在站点上。

几个值得知道的处理规则：

| 场景 | 处理方式 |
|---|---|
| 资源目录名不统一（`figures/` / `images/` / `context_engineering_2_figures/`） | 不硬编码目录名，扫描主题目录下所有含图片的子目录并整体拷贝 |
| 文件名含中文/空格（如 PDF） | slug 只保留 ASCII 部分；为空或冲突时追加内容 hash。中文标题保留在 `title` 里正常显示 |
| 文档开头的 `资料来源：` 区块 | 由 `splitSources()` 从正文剥离，单独渲染在标题下方，避免正文一上来就是一堆链接 |
| 卡片摘要 | 优先用根 `README.md` 「当前内容」表格里已维护好的摘要；没有则取正文首段 |
| 跨文档相对链接 | 重写成站内路由；指向 `docs/` 之外的（如 `../../demo/...`）重写成 GitHub blob 链接 |
| 无法解析的 `.md` 链接 | 保留原样并在构建日志 warn，不静默产生死链 |

## 需要手工维护的只有一个文件

`src/lib/categories.ts`：决定侧边分组、主题标签，以及少数需要覆盖标题/摘要的文档
（比如没有 H1 的那篇）。

没有归入任何分类的主题会落到末尾的「其他」分组，并在构建日志里提示 —— 忘了配也不会
从站点上消失。

## 主题

两套 design token，通过 `<html data-theme>` 切换，localStorage 持久化，
`layout.tsx` 里的内联脚本在首屏绘制前应用以避免闪烁：

- `src/styles/tokens-midnight.css` —— 深色（默认）
- `src/styles/tokens-parchment.css` —— 浅色（暖奶油 + 墨绿，serif）
- `src/styles/shell.css` —— 组件层，消费上面的 token；含完整的响应式与 `@media print` 规则
