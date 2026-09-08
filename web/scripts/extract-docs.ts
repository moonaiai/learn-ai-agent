/**
 * Build-time content extractor.
 *
 * Recursively scans `docs/` at the repo root, renders every Markdown file to
 * HTML, copies image assets, PDFs and standalone HTML pages into `public/`, and
 * writes two JSON files that the Next.js pages consume:
 *
 *   src/data/generated/docs.json  — full entries including rendered HTML
 *   src/data/generated/nav.json   — the same minus HTML, for layout/home/nav
 *
 * Adding a document to `docs/` requires no changes here or in categories.ts;
 * an unmapped topic lands in the "其他" group with a warning.
 */
import * as fs from "fs";
import * as path from "path";
import {
  CATEGORIES,
  FALLBACK_CATEGORY,
  DOC_OVERRIDES,
  TOPIC_LABELS,
  categoryForTopic,
} from "../src/lib/categories";
import {
  renderMarkdown,
  extractHeadings,
  titleFromMarkdown,
  summaryFromMarkdown,
  splitSources,
} from "../src/lib/markdown";
import { slugify, uniqueSlug } from "../src/lib/slug";
import type { DocEntry, NavCategory, NavEntry, NavIndex } from "../src/lib/types";

const WEB_DIR = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(WEB_DIR, "..");
const DOCS_ROOT = path.join(REPO_ROOT, "docs");
const OUT_DIR = path.join(WEB_DIR, "src", "data", "generated");
const PUBLIC_DIR = path.join(WEB_DIR, "public");
const ASSETS_OUT = path.join(PUBLIC_DIR, "doc-assets");
const PDF_OUT = path.join(PUBLIC_DIR, "doc-pdf");
const HTML_OUT = path.join(PUBLIC_DIR, "doc-html");

/** Public URL prefix. Empty for local dev; `/learn-ai-agent` on GitHub Pages. */
const ASSET_BASE = process.env.NEXT_BASE_PATH ?? "";

const GITHUB_BLOB = "https://github.com/moonaiai/learn-ai-agent/blob/main";

const IMAGE_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".webp",
]);

/**
 * Courses linked to a doc category via their course.json `docCategories`
 * field — surfaced on the track page as "相关课程". Loaded best-effort: the
 * courses extractor runs after this one, so we read the manifests directly.
 */
function coursesByCategory(): Map<string, { id: string; title: string }[]> {
  const map = new Map<string, { id: string; title: string }[]>();
  const coursesRoot = path.join(REPO_ROOT, "courses");
  if (!fs.existsSync(coursesRoot)) return map;
  for (const entry of fs.readdirSync(coursesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const manifestPath = path.join(coursesRoot, entry.name, "course.json");
    if (!fs.existsSync(manifestPath)) continue;
    try {
      const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
      const item = { id: slugify(entry.name), title: manifest.title ?? entry.name };
      for (const categoryId of manifest.docCategories ?? []) {
        if (!map.has(categoryId)) map.set(categoryId, []);
        map.get(categoryId)!.push(item);
      }
    } catch {
      // Malformed manifest — the courses extractor will report it.
    }
  }
  return map;
}

interface SourceFile {
  /** First-level directory under `docs/`. */
  topic: string;
  /** Path relative to `docs/`, e.g. `transformer/01-x.md`. */
  relPath: string;
  absPath: string
  kind: "md" | "pdf" | "html";
}

const warnings: string[] = [];

function warn(message: string) {
  warnings.push(message);
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/** Source extensions that become site pages, mapped to their doc kind. */
const SOURCE_KINDS: Record<string, SourceFile["kind"]> = {
  ".md": "md",
  ".pdf": "pdf",
  ".html": "html",
  ".htm": "html",
};

function discover(): SourceFile[] {
  const found: SourceFile[] = [];

  function walk(dir: string) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
        continue;
      }
      const ext = path.extname(entry.name).toLowerCase();
      const kind = SOURCE_KINDS[ext];
      if (!kind) continue;

      const relPath = path.relative(DOCS_ROOT, abs);
      const topic = relPath.split(path.sep)[0];
      // A file sitting directly in docs/ has no topic directory.
      if (relPath.split(path.sep).length < 2) {
        warn(`跳过 docs/ 根目录下的文件（需放在主题目录内）: ${relPath}`);
        continue;
      }
      found.push({ topic, relPath, absPath: abs, kind });
    }
  }

  walk(DOCS_ROOT);
  return found.sort((a, b) => a.relPath.localeCompare(b.relPath));
}

// ---------------------------------------------------------------------------
// Assets
// ---------------------------------------------------------------------------

function dirHasImages(dir: string): boolean {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .some(
      (entry) =>
        entry.isFile() && IMAGE_EXTENSIONS.has(path.extname(entry.name).toLowerCase())
    );
}

/**
 * Copy every image-bearing subdirectory of each topic into
 * `public/doc-assets/<topic>/<subdir>/`, keeping the original subdirectory name.
 *
 * Asset directories are not consistently named in this repo — `figures/` for
 * most topics, `images/` for build-agent-context-engineering,
 * `context_engineering_2_figures/` for context-engineering-2.0-pdf — so the
 * name is discovered rather than hardcoded.
 *
 * Returns the set of copied `<topic>/<subdir>` pairs, used to validate image
 * links during rewriting.
 */
function copyAssets(topics: string[]): Set<string> {
  fs.rmSync(ASSETS_OUT, { recursive: true, force: true });
  const copied = new Set<string>();
  let fileCount = 0;

  for (const topic of topics) {
    const topicDir = path.join(DOCS_ROOT, topic);
    if (!fs.existsSync(topicDir)) continue;

    for (const entry of fs.readdirSync(topicDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const srcDir = path.join(topicDir, entry.name);
      if (!dirHasImages(srcDir)) continue;

      const destDir = path.join(ASSETS_OUT, topic, entry.name);
      fs.mkdirSync(destDir, { recursive: true });
      fs.cpSync(srcDir, destDir, { recursive: true });
      // .DS_Store files litter several of these directories.
      for (const junk of ["\.DS_Store"]) {
        const junkPath = path.join(destDir, junk.replace("\\", ""));
        fs.rmSync(junkPath, { force: true });
      }
      copied.add(`${topic}/${entry.name}`);
      fileCount += fs.readdirSync(destDir).length;
    }
  }

  console.log(`  资源目录 ${copied.size} 个，图片文件 ${fileCount} 个`);
  return copied;
}

function copyPdf(source: SourceFile, topic: string, slug: string): number {
  const destDir = path.join(PDF_OUT, topic);
  fs.mkdirSync(destDir, { recursive: true });
  const dest = path.join(destDir, `${slug}.pdf`);
  fs.copyFileSync(source.absPath, dest);
  return fs.statSync(dest).size;
}

/**
 * Copy a standalone HTML document into `public/doc-html/<topic>/<slug>.html`.
 *
 * These are self-contained pages (slide decks, interactive demos) authored
 * outside this site — they ship their own `<style>`, scripts and key handlers,
 * and several assume they own the whole viewport. So they are served verbatim
 * from `public/` and shown in an iframe rather than merged into the prose
 * pipeline, which keeps their CSS and this site's CSS from colliding.
 */
function copyHtml(source: SourceFile, topic: string, slug: string): number {
  const destDir = path.join(HTML_OUT, topic);
  fs.mkdirSync(destDir, { recursive: true });
  const dest = path.join(destDir, `${slug}.html`);
  fs.copyFileSync(source.absPath, dest);
  return fs.statSync(dest).size;
}

// ---------------------------------------------------------------------------
// Standalone HTML metadata
// ---------------------------------------------------------------------------

function decodeEntities(text: string): string {
  const named: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: " ",
  };
  return text
    .replace(/&#(\d+);/g, (_, code: string) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-f]+);/gi, (_, code: string) =>
      String.fromCodePoint(parseInt(code, 16))
    )
    .replace(/&([a-z]+);/gi, (match, name: string) => named[name.toLowerCase()] ?? match);
}

/**
 * Pull a display title and summary out of a standalone HTML document, so it
 * gets the same card treatment as Markdown without a hand-written override.
 *
 * Title falls back through `<title>` → first `<h1>` → filename; summary uses
 * `<meta name="description">` when present. The `<title>` of these decks often
 * carries a subtitle after an em-dash (e.g. "Agent 经济学 — Token 预算…"), which
 * makes a better summary than a duplicate of the title, so it is split off.
 */
function htmlMetadata(
  absPath: string,
  fallbackTitle: string
): { title: string; summary?: string } {
  const head = fs.readFileSync(absPath, "utf-8").slice(0, 200_000);

  const clean = (value: string | undefined) =>
    value ? decodeEntities(value.replace(/<[^>]*>/g, "")).replace(/\s+/g, " ").trim() : "";

  const rawTitle =
    clean(/<title[^>]*>([\s\S]*?)<\/title>/i.exec(head)?.[1]) ||
    clean(/<h1[^>]*>([\s\S]*?)<\/h1>/i.exec(head)?.[1]);

  const description = clean(
    /<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']/i.exec(head)?.[1]
  );

  if (!rawTitle) {
    return { title: fallbackTitle, summary: description || undefined };
  }

  // Split "主标题 — 副标题" into title + summary when there is no meta description.
  const [, main, subtitle] = /^(.+?)\s+[—–-]{1,2}\s+(.+)$/.exec(rawTitle) ?? [];
  if (!description && main && subtitle) {
    return { title: main.trim(), summary: subtitle.trim() };
  }

  return { title: rawTitle, summary: description || undefined };
}

// ---------------------------------------------------------------------------
// README summaries
// ---------------------------------------------------------------------------

/**
 * Harvest the curated one-line summaries already maintained in the root
 * README.md's "当前内容" table, keyed by `docs/`-relative source path.
 *
 * Rows look like:
 *   | 12-Factor Agents | [标题](docs/12-factor-agents/x.md) | 从 agent loop… |
 *
 * These read far better on the home page than the first paragraph of each
 * document, which is usually a `资料来源：` attribution block. Only 3+ column
 * rows whose second cell is a single doc link are considered, so the learning
 * path table (which lists several links per cell) is skipped.
 */
function readmeSummaries(): Map<string, string> {
  const summaries = new Map<string, string>();
  const readmePath = path.join(REPO_ROOT, "README.md");
  if (!fs.existsSync(readmePath)) return summaries;

  for (const line of fs.readFileSync(readmePath, "utf-8").split("\n")) {
    if (!line.startsWith("|")) continue;
    const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
    if (cells.length < 3) continue;

    const links = [...cells[1].matchAll(/\[[^\]]*\]\((docs\/[^)]+\.md)\)/g)];
    if (links.length !== 1) continue;

    const summary = cells[2].replace(/\s+/g, " ").trim();
    if (!summary || summary.length < 12) continue;

    const relPath = links[0][1].replace(/^docs\//, "");
    if (!summaries.has(relPath)) summaries.set(relPath, summary);
  }

  return summaries;
}

// ---------------------------------------------------------------------------
// Link rewriting
// ---------------------------------------------------------------------------

/**
 * Rewrite Markdown links and image references to site-absolute URLs.
 *
 * - `figures/x.png` → `${ASSET_BASE}/doc-assets/<topic>/figures/x.png`
 * - `../kv-cache/01-x.md` → `${ASSET_BASE}/docs/kv-cache/<slug>/`
 * - anything resolving outside `docs/` → the GitHub blob URL
 * - `#anchor` and absolute URLs are left alone
 *
 * `routeByRelPath` maps a `docs/`-relative source path to its site route, so
 * cross-document links follow the same slugging rules as the pages themselves.
 * Routes passed in here must already include the basePath — these anchors are
 * plain HTML and bypass Next.js routing.
 */
function rewriteLinks(
  markdown: string,
  source: SourceFile,
  routeByRelPath: Map<string, string>,
  assetDirs: Set<string>
): string {
  const sourceDir = path.dirname(source.relPath);

  return markdown.replace(
    /(!?)\[([^\]]*)\]\(([^)\s]+)([^)]*)\)/g,
    (match, bang: string, text: string, target: string, tail: string) => {
      // Leave anchors, absolute URLs and protocol-relative links untouched.
      if (/^(#|[a-z][a-z0-9+.-]*:|\/\/)/i.test(target)) return match;
      if (target.startsWith("/")) return match;

      const [rawPath, hash = ""] = target.split("#");
      if (!rawPath) return match;

      // Resolve relative to the document, keeping it inside docs/ when possible.
      const resolvedFromDocs = path.normalize(path.join(sourceDir, rawPath));
      const escapesDocs = resolvedFromDocs.startsWith("..");

      if (escapesDocs) {
        // e.g. ../../demo/evaluation_frameworks/README.md
        const fromRepoRoot = path
          .normalize(path.join("docs", sourceDir, rawPath))
          .split(path.sep)
          .join("/");
        return `${bang}[${text}](${GITHUB_BLOB}/${fromRepoRoot}${
          hash ? `#${hash}` : ""
        }${tail})`;
      }

      const posixPath = resolvedFromDocs.split(path.sep).join("/");
      const ext = path.extname(posixPath).toLowerCase();

      if (IMAGE_EXTENSIONS.has(ext)) {
        const assetDir = path.dirname(posixPath);
        if (!assetDirs.has(assetDir)) {
          warn(`图片资源目录未被拷贝: ${source.relPath} → ${rawPath}`);
        }
        return `${bang}[${text}](${ASSET_BASE}/doc-assets/${posixPath}${tail})`;
      }

      if (ext === ".md" || ext === ".pdf" || ext === ".html" || ext === ".htm") {
        const route = routeByRelPath.get(posixPath);
        if (route) {
          return `${bang}[${text}](${route}${hash ? `#${hash}` : ""}${tail})`;
        }
        warn(`交叉链接无法解析，保留原样: ${source.relPath} → ${rawPath}`);
        return match;
      }

      return match;
    }
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  console.log("提取 docs/ 内容…");
  console.log(`  仓库根目录: ${REPO_ROOT}`);
  if (ASSET_BASE) console.log(`  basePath: ${ASSET_BASE}`);

  if (!fs.existsSync(DOCS_ROOT)) {
    throw new Error(`找不到 docs 目录: ${DOCS_ROOT}`);
  }

  const sources = discover();
  const topics = Array.from(new Set(sources.map((s) => s.topic)));
  console.log(`  发现 ${sources.length} 个文件，${topics.length} 个主题目录`);

  const assetDirs = copyAssets(topics);

  fs.rmSync(PDF_OUT, { recursive: true, force: true });
  fs.rmSync(HTML_OUT, { recursive: true, force: true });

  // Pass 1: assign slugs and routes so links can be resolved in pass 2.
  // Two forms per document: `route` for next/link (no basePath — Next prepends
  // it), and `hrefByRelPath` for raw anchors inside rendered Markdown, which
  // bypass Next's routing and therefore need the prefix baked in.
  const takenSlugs = new Map<string, Set<string>>();
  const routeByRelPath = new Map<string, string>();
  const hrefByRelPath = new Map<string, string>();
  const slugByRelPath = new Map<string, string>();

  // Reserve every pinned slug first, so an auto-derived slug can never claim
  // one out from under an override (discovery order would otherwise decide).
  for (const source of sources) {
    const posixRel = source.relPath.split(path.sep).join("/");
    const pinned = DOC_OVERRIDES[posixRel]?.slug;
    if (!pinned) continue;
    const topicSlug = slugify(source.topic) || "topic";
    if (!takenSlugs.has(topicSlug)) takenSlugs.set(topicSlug, new Set());
    const taken = takenSlugs.get(topicSlug)!;
    if (taken.has(pinned)) {
      warn(`slug 覆盖重复，后者将覆盖前者: ${posixRel} → ${pinned}`);
    }
    taken.add(pinned);
  }

  for (const source of sources) {
    const topicSlug = slugify(source.topic) || "topic";
    const basename = path.basename(source.relPath, path.extname(source.relPath));
    if (!takenSlugs.has(topicSlug)) takenSlugs.set(topicSlug, new Set());

    const posixRel = source.relPath.split(path.sep).join("/");
    const taken = takenSlugs.get(topicSlug)!;
    // Pinned slugs were reserved above; everything else fills the gaps.
    const slug =
      DOC_OVERRIDES[posixRel]?.slug ?? uniqueSlug(basename, source.relPath, taken);

    const route = `/docs/${topicSlug}/${slug}/`;
    slugByRelPath.set(posixRel, slug);
    routeByRelPath.set(posixRel, route);
    hrefByRelPath.set(posixRel, `${ASSET_BASE}${route}`);
  }

  // Pass 2: render.
  const docs: DocEntry[] = [];
  const curated = readmeSummaries();
  console.log(`  README 摘要 ${curated.size} 条`);

  for (const source of sources) {
    const posixRel = source.relPath.split(path.sep).join("/");
    const topicSlug = slugify(source.topic) || "topic";
    const slug = slugByRelPath.get(posixRel)!;
    const route = routeByRelPath.get(posixRel)!;
    const override = DOC_OVERRIDES[posixRel] ?? {};
    const category = categoryForTopic(source.topic);
    const sourcePath = `docs/${posixRel}`;

    const base = {
      topic: topicSlug,
      slug,
      route,
      topicLabel: TOPIC_LABELS[source.topic] ?? source.topic,
      categoryId: category.id,
      sourcePath,
      githubUrl: `${GITHUB_BLOB}/${sourcePath.split("/").map(encodeURIComponent).join("/")}`,
    };

    if (source.kind === "pdf") {
      const bytes = copyPdf(source, topicSlug, slug);
      docs.push({
        ...base,
        kind: "pdf",
        title: override.title ?? path.basename(source.relPath, ".pdf"),
        summary: override.summary ?? "PDF 文档。",
        headings: [],
        pdfUrl: `${ASSET_BASE}/doc-pdf/${topicSlug}/${slug}.pdf`,
        bytes,
      });
      continue;
    }

    if (source.kind === "html") {
      const bytes = copyHtml(source, topicSlug, slug);
      const ext = path.extname(source.relPath);
      const meta = htmlMetadata(source.absPath, path.basename(source.relPath, ext));
      docs.push({
        ...base,
        kind: "html",
        title: override.title ?? meta.title,
        summary: override.summary ?? meta.summary ?? "独立 HTML 页面。",
        headings: [],
        embedUrl: `${ASSET_BASE}/doc-html/${topicSlug}/${slug}.html`,
        bytes,
      });
      continue;
    }

    const raw = fs.readFileSync(source.absPath, "utf-8");
    const rewritten = rewriteLinks(raw, source, hrefByRelPath, assetDirs);

    const title =
      override.title ??
      titleFromMarkdown(rewritten) ??
      (() => {
        warn(`缺少 H1 标题且无 override，回退到文件名: ${posixRel}`);
        return path.basename(source.relPath, ".md");
      })();

    const { sources, body } = splitSources(rewritten);

    docs.push({
      ...base,
      kind: "md",
      title,
      // Priority: explicit override → curated README summary → first paragraph.
      summary:
        override.summary ??
        curated.get(posixRel) ??
        summaryFromMarkdown(rewritten),
      headings: extractHeadings(body),
      html: renderMarkdown(body),
      sourcesHtml: sources ? renderMarkdown(sources) : undefined,
    });
  }

  // Group into categories, preserving CATEGORIES order then topic order.
  const categories: NavCategory[] = [];
  const toNav = ({ html: _html, sourcesHtml: _sourcesHtml, ...rest }: DocEntry): NavEntry =>
    rest;

  const linkedCourses = coursesByCategory();

  // A representative image per category for the track card's visual — the
  // first image asset of the first topic in the category that has one.
  function coverForCategory(category: (typeof CATEGORIES)[number]): string | undefined {
    for (const topic of category.topics) {
      for (const copied of assetDirs) {
        const [assetTopic, assetSubdir] = copied.split("/");
        if (assetTopic !== topic) continue;
        const dir = path.join(ASSETS_OUT, copied);
        if (!fs.existsSync(dir)) continue;
        const file = fs
          .readdirSync(dir)
          .find((name) => IMAGE_EXTENSIONS.has(path.extname(name).toLowerCase()));
        if (file) {
          return `${ASSET_BASE}/doc-assets/${copied}/${file}`;
        }
      }
    }
    return undefined;
  }

  for (const category of [...CATEGORIES, FALLBACK_CATEGORY]) {
    const inCategory = docs.filter((doc) => doc.categoryId === category.id);
    if (inCategory.length === 0) continue;

    // Order by the topic order declared in categories.ts, then by slug.
    const topicRank = new Map(category.topics.map((t, i) => [slugify(t), i]));
    inCategory.sort((a, b) => {
      const rankDiff =
        (topicRank.get(a.topic) ?? 999) - (topicRank.get(b.topic) ?? 999);
      if (rankDiff !== 0) return rankDiff;
      return a.slug.localeCompare(b.slug);
    });

    categories.push({
      id: category.id,
      label: category.label,
      blurb: category.blurb,
      docs: inCategory.map(toNav),
      courses: linkedCourses.get(category.id) ?? [],
      coverUrl: coverForCategory(category),
    });
  }

  const unmapped = topics.filter(
    (topic) => categoryForTopic(topic).id === FALLBACK_CATEGORY.id
  );
  for (const topic of unmapped) {
    warn(`主题未归入分类映射表，已放入「其他」: ${topic}（编辑 src/lib/categories.ts）`);
  }

  const ordered = categories.flatMap((category) => category.docs);
  const nav: NavIndex = {
    categories,
    ordered,
    stats: {
      markdown: docs.filter((doc) => doc.kind === "md").length,
      pdf: docs.filter((doc) => doc.kind === "pdf").length,
      html: docs.filter((doc) => doc.kind === "html").length,
      categories: categories.length,
    },
  };

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUT_DIR, "docs.json"), JSON.stringify(docs));
  fs.writeFileSync(path.join(OUT_DIR, "nav.json"), JSON.stringify(nav, null, 2));

  console.log("\n提取完成：");
  console.log(`  Markdown ${nav.stats.markdown} 篇，PDF ${nav.stats.pdf} 份，HTML ${nav.stats.html} 个`);
  console.log(`  分类 ${nav.stats.categories} 组`);
  for (const category of categories) {
    console.log(`    ${category.label}: ${category.docs.length} 篇`);
  }

  if (warnings.length > 0) {
    console.log(`\n⚠ ${warnings.length} 条提示：`);
    for (const message of warnings) console.log(`  - ${message}`);
  } else {
    console.log("\n无告警。");
  }
}

main();
