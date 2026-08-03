import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkRehype from "remark-rehype";
import rehypeRaw from "rehype-raw";
import rehypeSlug from "rehype-slug";
import rehypeHighlight from "rehype-highlight";
import rehypeStringify from "rehype-stringify";
import { visit } from "unist-util-visit";
import type { Root, Heading as MdHeading } from "mdast";
import GithubSlugger from "github-slugger";
import type { Heading } from "./types";

/**
 * Markdown → HTML. Runs at build time only (from scripts/extract-docs.ts), so
 * none of the unified toolchain ends up in the client bundle.
 */
export function renderMarkdown(markdown: string): string {
  const file = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkRehype, { allowDangerousHtml: true })
    .use(rehypeRaw)
    .use(rehypeSlug)
    .use(rehypeHighlight, { detect: false, ignoreMissing: true })
    .use(rehypeStringify, { allowDangerousHtml: true })
    .processSync(markdown);

  return postProcessHtml(String(file));
}

/**
 * Extract h2/h3 headings for the table of contents. Uses the same slugger
 * algorithm as rehype-slug (github-slugger) so the ids match the rendered HTML,
 * including its duplicate-suffix behaviour.
 */
export function extractHeadings(markdown: string): Heading[] {
  const tree = unified().use(remarkParse).use(remarkGfm).parse(markdown) as Root;
  const slugger = new GithubSlugger();
  const headings: Heading[] = [];

  visit(tree, "heading", (node: MdHeading) => {
    const text = mdastToString(node).trim();
    if (!text) return;
    // Slug every heading level so the counter stays in sync with rehype-slug,
    // but only surface h2/h3 in the TOC.
    const id = slugger.slug(text);
    if (node.depth === 2 || node.depth === 3) {
      headings.push({ depth: node.depth, text, id });
    }
  });

  return headings;
}

/** First `# H1` in the document, or null. */
export function titleFromMarkdown(markdown: string): string | null {
  const match = markdown.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : null;
}

const ATTRIBUTION_LEAD = /^>?\s*(资料来源|资源来源|原文|来源|参考资料)[:：]?\s*$|^>?\s*(资料来源|资源来源|原文|来源|参考资料)[:：]/;

/**
 * Split the leading source-attribution preamble off the top of a document.
 *
 * Most docs in this repo open with a `资料来源：` block listing the upstream
 * article or paper before the first `##` section. Rendering that inline makes
 * every page start with a wall of links; pulling it out lets the page show it
 * once, compactly, next to the title.
 *
 * Returns the preamble Markdown (may be empty) and the remaining body.
 */
export function splitSources(markdown: string): {
  sources: string;
  body: string;
} {
  const withoutTitle = markdown.replace(/^#\s+.+\n?/m, "");
  const blocks = withoutTitle.split(/\n{2,}/);

  const taken: string[] = [];
  let index = 0;

  // Skip leading blank blocks.
  while (index < blocks.length && !blocks[index].trim()) index += 1;

  if (index < blocks.length && ATTRIBUTION_LEAD.test(blocks[index].trim())) {
    taken.push(blocks[index]);
    index += 1;
    // A bare "资料来源：" label is followed by the list of links.
    while (index < blocks.length) {
      const block = blocks[index].trim();
      if (!block) break;
      if (block.startsWith("#")) break;
      if (!/^([-*+]\s|\[|>|\d+\.\s|https?:)/.test(block)) break;
      taken.push(blocks[index]);
      index += 1;
    }
  }

  if (taken.length === 0) {
    return { sources: "", body: withoutTitle };
  }

  return {
    sources: taken.join("\n\n").replace(/^>\s?/gm, "").trim(),
    body: blocks.slice(index).join("\n\n"),
  };
}

/**
 * First prose paragraph after the H1 — the fallback card summary when the README
 * has no curated one. Skips blockquotes, images, tables, lists, headings and the
 * `资料来源：` attribution blocks that open most documents in this repo.
 */
export function summaryFromMarkdown(markdown: string, maxLength = 130): string {
  const body = markdown.replace(/^#\s+.+$/m, "");
  const blocks = body.split(/\n{2,}/);

  for (const raw of blocks) {
    const block = raw.trim();
    if (!block) continue;
    if (/^[#>|\-*+]|^\d+\.|^!\[|^```|^<|^\|/.test(block)) continue;
    // Source-attribution preamble, not a summary.
    if (/^(资料来源|原文|来源|参考资料|资源来源)[:：]/.test(block)) continue;

    const text = block
      .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
      .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/[*_`]/g, "")
      .replace(/\s+/g, " ")
      .trim();

    if (text.length < 12) continue;
    return text.length > maxLength ? `${text.slice(0, maxLength)}…` : text;
  }

  return "";
}

const LANGUAGE_LABELS: Record<string, string> = {
  ts: "TypeScript",
  tsx: "TSX",
  js: "JavaScript",
  jsx: "JSX",
  py: "Python",
  python: "Python",
  bash: "Bash",
  sh: "Shell",
  shell: "Shell",
  zsh: "Shell",
  json: "JSON",
  yaml: "YAML",
  yml: "YAML",
  toml: "TOML",
  go: "Go",
  rust: "Rust",
  java: "Java",
  sql: "SQL",
  text: "Text",
  plaintext: "Text",
  diff: "Diff",
  mermaid: "Mermaid",
  html: "HTML",
  css: "CSS",
  makefile: "Makefile",
  dockerfile: "Dockerfile",
};

function languageLabel(language: string): string {
  return LANGUAGE_LABELS[language.toLowerCase()] ?? language.toUpperCase();
}

/**
 * Rewrap the raw HTML from the unified pipeline into the shell.css component
 * structure: code cards with a toolbar, scrollable table wrappers, figures with
 * captions, and diagram cards for language-less preformatted blocks.
 */
function postProcessHtml(html: string): string {
  let out = html;

  // Highlighted code blocks → .code-card with a language label + copy button.
  out = out.replace(
    /<pre><code class="hljs language-([\w-]+)">/g,
    (_match, language: string) =>
      `<div class="code-card"><div class="code-toolbar"><span>${languageLabel(
        language
      )}</span><button class="copy-code" type="button" data-copy>复制</button></div>` +
      `<pre><code class="hljs language-${language}">`
  );

  // Language-less blocks (ASCII diagrams, plain output) → .diagram-card.
  out = out.replace(
    /<pre><code(?! class="hljs)([^>]*)>/g,
    '<div class="diagram-card"><pre><code$1>'
  );

  // Close whichever wrapper we opened. Both variants open exactly one <div>
  // immediately before their <pre>, so a single close per </pre> is correct.
  out = out.replace(/<\/code><\/pre>/g, "</code></pre></div>");

  // Wide Markdown tables need a horizontal scroll container.
  out = out.replace(/<table>/g, '<div class="table-wrap"><table>');
  out = out.replace(/<\/table>/g, "</table></div>");

  // Standalone images → <figure> with the alt text as a caption.
  out = out.replace(
    /<p>(<img [^>]*>)<\/p>/g,
    (_match, img: string) => {
      const altMatch = img.match(/alt="([^"]*)"/);
      const alt = altMatch?.[1] ?? "";
      const lazyImg = img.includes("loading=")
        ? img
        : img.replace(/<img /, '<img loading="lazy" ');
      const caption = alt ? `<figcaption>${alt}</figcaption>` : "";
      return `<figure class="doc-figure">${lazyImg}${caption}</figure>`;
    }
  );

  // The page header already renders the title.
  out = out.replace(/<h1[^>]*>[\s\S]*?<\/h1>\s*/, "");

  return out;
}

/** Concatenate the text content of an mdast node. */
function mdastToString(node: unknown): string {
  const n = node as { value?: string; children?: unknown[] };
  if (typeof n.value === "string") return n.value;
  if (Array.isArray(n.children)) return n.children.map(mdastToString).join("");
  return "";
}
