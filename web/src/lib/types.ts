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
  /**
   * Courses whose `docCategories` manifest field lists this category — shown
   * on the track page as "相关课程" next to the docs.
   */
  courses: { id: string; title: string }[];
  /**
   * Public URL (basePath included) of a representative image from the track's
   * asset folders — used as the track card's visual. Absent when the track
   * ships no images.
   */
  coverUrl?: string;
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

/* ---------------------------------------------------------------------------
 * Courses — structured curricula mirrored under `courses/<id>/`, parallel to
 * the flat docs pipeline. A course is an ordered tree of modules and lessons;
 * labs (notebook directories) are listed but link out to GitHub.
 * ------------------------------------------------------------------------- */

export type LessonKind = "lesson" | "lab";

export interface CourseLesson {
  /** Curriculum number, e.g. "2.3". Drives ordering and the TOC badge. */
  number: string;
  slug: string;
  /** Site route WITHOUT basePath, e.g. `/courses/agentic-ai/2-3-chart/`. */
  route: string;
  title: string;
  /** English half of the bilingual source filename, when present. */
  titleEn?: string;
  kind: LessonKind;
  /** `lab` only: GitHub URL of the mirrored notebook directory. */
  githubUrl?: string;
  headings: Heading[];
  /** Rendered HTML — `lesson` only. */
  html?: string;
}

export interface CourseModule {
  number: number;
  title: string;
  titleEn?: string;
  lessons: CourseLesson[];
}

export interface Course {
  id: string;
  title: string;
  subtitle?: string;
  instructor?: string;
  /** Upstream repository the content is mirrored from. */
  source?: string;
  /** External video course URL, when one exists. */
  video?: string;
  description: string;
  /** First course image, used as the course card's cover. */
  coverUrl?: string;
  modules: CourseModule[];
  /** All lessons flattened in curriculum order — used for prev/next. */
  ordered: CourseLesson[];
  stats: { lessons: number; labs: number };
}
