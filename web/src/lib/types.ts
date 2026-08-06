export interface Heading {
  depth: 2 | 3;
  text: string;
  id: string;
}

export type DocKind = "md" | "pdf" | "html";

/** One document. `html` (rendered content) is only present for `kind: "md"`. */
export interface DocEntry {
  topic: string;
  slug: string;
  /**
   * Site route WITHOUT the basePath, e.g. `/docs/transformer/01-x/`.
   * Intended for `next/link`, which prepends the basePath itself. Raw anchors
   * embedded in rendered Markdown carry the basePath already.
   */
  route: string;
  kind: DocKind;
  /** Display title (may contain CJK). */
  title: string;
  /** Short blurb for the home page cards. */
  summary: string;
  /** Human-readable topic label, used as the card eyebrow. */
  topicLabel: string;
  categoryId: string;
  /** Path relative to the repo root, e.g. `docs/transformer/01-x.md`. */
  sourcePath: string;
  /** Link to the source file on GitHub. */
  githubUrl: string;
  headings: Heading[];
  /** Rendered HTML — `md` only. */
  html?: string;
  /**
   * Rendered HTML of the leading `资料来源：` attribution block, lifted out of
   * the body so the page can show it once next to the title — `md` only.
   */
  sourcesHtml?: string;
  /** Public URL of the copied PDF, basePath included — `pdf` only. */
  pdfUrl?: string;
  /**
   * Public URL of the copied standalone HTML page, basePath included —
   * `html` only. Served verbatim from `public/`, outside Next's routing.
   */
  embedUrl?: string;
  /** Size of the source PDF or HTML file in bytes — `pdf` / `html` only. */
  bytes?: number;
}

/** Lightweight index: everything except the rendered HTML. */
export type NavEntry = Omit<DocEntry, "html" | "sourcesHtml">;

export interface NavCategory {
  id: string;
  label: string;
  blurb: string;
  docs: NavEntry[];
}

export interface NavIndex {
  categories: NavCategory[];
  /** All docs in category order — used for prev/next links. */
  ordered: NavEntry[];
  stats: {
    markdown: number;
    pdf: number;
    html: number;
    categories: number;
  };
}
