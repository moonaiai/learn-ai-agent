/**
 * Build-time course extractor.
 *
 * Scans `courses/<id>/` at the repo root — each one a mirror of an upstream
 * curriculum with a hand-written `course.json` manifest — and produces
 * `src/data/generated/courses.json`, the course counterpart of docs.json.
 *
 * Layout convention (numbers in directory/file names carry the ordering):
 *
 *   courses/agentic-ai/
 *     course.json                       — manifest: title, source, order, …
 *     images/…                          — referenced as ../images/x.png
 *     1. 模块名[Module Name]/            — `^(\d+)\.` → module, ordered by number
 *       1.1 课时名[Lesson].md           — `^(\d+)\.(\d+)` → lesson page
 *       1.2 实验名[Ungraded Lab- X]/    — numbered subdirectory → lab entry,
 *         notebook.ipynb                  listed in the syllabus, links to GitHub
 *
 * Adding a course means mirroring a directory and writing one course.json;
 * nothing in this file or the app router changes.
 *
 * Numeric ordering is deliberate: `5.10` must sort after `5.2`, which a plain
 * lexicographic sort gets wrong.
 */
import * as fs from "fs";
import * as path from "path";
import {
  renderMarkdown,
  extractHeadings,
  titleFromMarkdown,
} from "../src/lib/markdown";
import { slugify, uniqueSlug } from "../src/lib/slug";
import type {
  Course,
  CourseAttribution,
  CourseLesson,
  CourseModule,
  Heading,
} from "../src/lib/types";

const WEB_DIR = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(WEB_DIR, "..");
const COURSES_ROOT = path.join(REPO_ROOT, "courses");
const OUT_DIR = path.join(WEB_DIR, "src", "data", "generated");
const ASSETS_OUT = path.join(WEB_DIR, "public", "course-assets");

/** Public URL prefix. Empty for local dev; `/learn-ai-agent` on GitHub Pages. */
const ASSET_BASE = process.env.NEXT_BASE_PATH ?? "";

/** Mirrored content lives in this repo, so blob/tree links point at ourselves. */
const GITHUB_BLOB = "https://github.com/moonaiai/learn-ai-agent/blob/main";
const GITHUB_TREE = "https://github.com/moonaiai/learn-ai-agent/tree/main";

const IMAGE_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".svg",
  ".webp",
]);

const warnings: string[] = [];

function warn(message: string) {
  warnings.push(message);
}

/** Shape of the hand-maintained courses/<id>/course.json manifest. */
interface CourseManifest {
  title: string;
  subtitle?: string;
  instructor?: string;
  source?: string;
  video?: string;
  order?: number;
  description?: string;
  /**
   * 出处与授权声明 — mirrored content belongs to its original authors; this
   * site only aggregates and re-renders it. Shown on the course page and at
   * the foot of every lesson page.
   */
  attribution?: CourseAttribution;
  /** Doc categories (categories.ts ids) this course belongs to. */
  docCategories?: string[];
  /**
   * Course-relative image path used as the card cover, e.g. "images/1.2.1.png".
   * Falls back to the first image found in the course tree.
   */
  cover?: string;
}

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------

/**
 * Split a bilingual name like "Agentic工作流简介[Introduction to Agentic
 * Workflows]" into its Chinese and English halves. The bracketed tail is a
 * convention of the mirrored upstream repos; names without it come back with
 * `en` undefined.
 */
function splitBilingual(raw: string): { zh: string; en?: string } {
  const match = /^(.*?)\s*\[([^\]]+)\]\s*$/.exec(raw.trim());
  if (!match) return { zh: raw.trim() };
  return { zh: match[1].trim(), en: match[2].trim() };
}

const MODULE_NAME = /^(\d+)[.、]\s*(.+)$/;
const LESSON_NAME = /^(\d+)\.(\d+)\s*(.+)$/;

/** Ordering key for "10" vs "2": compare major, then minor, numerically. */
function compareNumbers(a: string, b: string): number {
  const [aMajor, aMinor = 0] = a.split(".").map(Number);
  const [bMajor, bMinor = 0] = b.split(".").map(Number);
  return aMajor - bMajor || aMinor - bMinor;
}

// ---------------------------------------------------------------------------
// Per-course extraction
// ---------------------------------------------------------------------------

function extractCourse(courseId: string, manifest: CourseManifest): Course {
  const courseDir = path.join(COURSES_ROOT, courseId);
  const takenSlugs = new Set<string>();

  interface PendingLesson {
    number: string;
    title: string;
    titleEn?: string;
    slug: string;
    absPath: string;
    /** Course-relative posix path, e.g. `agentic-ai` stripped. */
    relPath: string;
    moduleDirName: string;
    moduleNumber: number;
  }
  interface LabEntry {
    number: string;
    title: string;
    titleEn?: string;
    githubUrl: string;
    moduleNumber: number;
  }

  const pending: PendingLesson[] = [];
  const labs: LabEntry[] = [];
  const moduleNames = new Map<number, { zh: string; en?: string }>();
  /** Course-relative posix path → site route, for cross-lesson links. */
  const routeByRelPath = new Map<string, string>();

  // Pass 1: discover lessons and labs, assign slugs and routes.
  const moduleDirs = fs
    .readdirSync(courseDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && MODULE_NAME.test(entry.name))
    .sort((a, b) => compareNumbers(a.name, b.name));

  for (const moduleDir of moduleDirs) {
    const [, moduleNumber, moduleRest] = MODULE_NAME.exec(moduleDir.name)!;
    moduleNames.set(Number(moduleNumber), splitBilingual(moduleRest));
    const moduleAbs = path.join(courseDir, moduleDir.name);

    for (const entry of fs.readdirSync(moduleAbs, { withFileTypes: true })) {
      const lessonMatch = LESSON_NAME.exec(entry.name);

      if (entry.isDirectory() && lessonMatch) {
        // A numbered subdirectory is a lab: notebooks and data, no page.
        const name = splitBilingual(lessonMatch[3]);
        labs.push({
          number: `${lessonMatch[1]}.${lessonMatch[2]}`,
          title: name.zh,
          titleEn: name.en,
          githubUrl: `${GITHUB_TREE}/courses/${encodeURIComponent(courseId)}/${encodeURIComponent(moduleDir.name)}/${encodeURIComponent(entry.name)}`,
          moduleNumber: Number(moduleNumber),
        });
        continue;
      }

      if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".md")) continue;
      if (!lessonMatch) {
        warn(`模块内文件名不符合「数字.数字」课时约定,已跳过: ${moduleDir.name}/${entry.name}`);
        continue;
      }

      const basename = entry.name.replace(/\.md$/i, "");
      const name = splitBilingual(lessonMatch[3].replace(/\.md$/i, ""));
      const slug = uniqueSlug(basename, `${courseId}/${moduleDir.name}/${entry.name}`, takenSlugs);
      const relPath = `${moduleDir.name}/${entry.name}`;
      const route = `/courses/${slugify(courseId)}/${slug}/`;

      pending.push({
        number: `${lessonMatch[1]}.${lessonMatch[2]}`,
        title: name.zh,
        titleEn: name.en,
        slug,
        absPath: path.join(moduleAbs, entry.name),
        relPath,
        moduleDirName: moduleDir.name,
        moduleNumber: Number(moduleNumber),
      });
      routeByRelPath.set(relPath.split(path.sep).join("/"), route);
    }
  }

  // Pass 2: render lessons now that every route is known.
  const lessonsByModule = new Map<number, CourseLesson[]>();
  const normalizedIndex = buildNormalizedIndex(courseId);

  for (const lesson of pending) {
    const raw = fs.readFileSync(lesson.absPath, "utf-8");
    const rewritten = rewriteLinks(
      raw,
      courseId,
      lesson.moduleDirName,
      routeByRelPath,
      normalizedIndex
    );
    const title =
      lesson.title ||
      titleFromMarkdown(raw) ||
      (() => {
        warn(`课时缺少标题,回退到文件名: ${lesson.relPath}`);
        return lesson.slug;
      })();

    const entry: CourseLesson = {
      number: lesson.number,
      slug: lesson.slug,
      route: routeByRelPath.get(lesson.relPath.split(path.sep).join("/"))!,
      title,
      titleEn: lesson.titleEn,
      kind: "lesson",
      githubUrl: `${GITHUB_BLOB}/courses/${encodeURIComponent(courseId)}/${lesson.relPath.split(path.sep).map(encodeURIComponent).join("/")}`,
      headings: extractHeadings(rewritten) as Heading[],
      html: renderMarkdown(rewritten),
    };
    if (!lessonsByModule.has(lesson.moduleNumber)) lessonsByModule.set(lesson.moduleNumber, []);
    lessonsByModule.get(lesson.moduleNumber)!.push(entry);
  }

  for (const lab of labs) {
    const entry: CourseLesson = {
      number: lab.number,
      slug: "",
      route: "",
      title: lab.title,
      titleEn: lab.titleEn,
      kind: "lab",
      githubUrl: lab.githubUrl,
      headings: [],
    };
    if (!lessonsByModule.has(lab.moduleNumber)) lessonsByModule.set(lab.moduleNumber, []);
    lessonsByModule.get(lab.moduleNumber)!.push(entry);
  }

  const modules: CourseModule[] = Array.from(moduleNames.entries())
    .sort(([a], [b]) => a - b)
    .map(([number, name]) => ({
      number,
      title: name.zh,
      titleEn: name.en,
      lessons: (lessonsByModule.get(number) ?? []).sort((a, b) =>
        compareNumbers(a.number, b.number)
      ),
    }));

  const ordered = modules.flatMap((module) => module.lessons);

  return {
    id: slugify(courseId),
    title: manifest.title,
    subtitle: manifest.subtitle,
    instructor: manifest.instructor,
    source: manifest.source,
    video: manifest.video,
    description: manifest.description ?? "",
    attribution: manifest.attribution,
    modules,
    ordered,
    stats: {
      lessons: ordered.filter((lesson) => lesson.kind === "lesson").length,
      labs: ordered.filter((lesson) => lesson.kind === "lab").length,
    },
  };
}

// ---------------------------------------------------------------------------
// Link rewriting — course-internal relative links
// ---------------------------------------------------------------------------

/**
 * Decode + normalize a raw link target (URL-encoded or Windows-backslashed)
 * against a lesson inside `moduleDirName`, and report where it lands.
 */
function resolveAgainstModule(
  courseId: string,
  moduleDirName: string,
  rawPath: string
): { resolved: string; posixRel: string; outside: boolean } {
  const sourceDir = path.join(COURSES_ROOT, courseId, moduleDirName);
  let decodedPath = rawPath;
  try {
    decodedPath = decodeURIComponent(rawPath);
  } catch {
    // A literal `%` in the path — treat it as-is.
  }
  // Some upstream files were authored on Windows (`..\images\x.png`).
  decodedPath = decodedPath.replace(/\\/g, "/");
  const resolved = path.normalize(path.join(sourceDir, decodedPath));
  const relToCourse = path.relative(path.join(COURSES_ROOT, courseId), resolved);
  return {
    resolved,
    posixRel: relToCourse.split(path.sep).join("/"),
    outside: relToCourse.startsWith(".."),
  };
}

/** GitHub URL for a course-tree file, as seen from the repo root. */
function githubBlobUrl(courseId: string, moduleDirName: string, decodedPath: string): string {
  const fromRepoRoot = path
    .normalize(path.join("courses", courseId, moduleDirName, decodedPath))
    .split(path.sep)
    .join("/");
  return `${GITHUB_BLOB}/${fromRepoRoot.split("/").map(encodeURIComponent).join("/")}`;
}

/**
 * Canonical form of one path segment: upstream books number their parts and
 * chapters differently from the mirrored layout (`Part9-前沿实践` vs
 * `9. 前沿实践`, `第33章：X.md` vs `9.33 X.md`), so links whose exact path
 * misses the mirror get a second chance through this normalization. The
 * numeric rule requires trailing whitespace — figure names like `1.2.2.png`
 * must survive untouched.
 */
function stripNumbering(segment: string): string {
  return segment
    .replace(/^Part\d+-/, "")
    .replace(/^第\d+章：/, "")
    .replace(/^\d+(?:[.、]\d+)?\s+/, "");
}

/**
 * Every file in the course tree, keyed by its normalized course-relative
 * path. Built once per course; only consulted when an exact-path lookup has
 * already missed, so collisions are reported and the first file wins.
 */
function buildNormalizedIndex(courseId: string): Map<string, string> {
  const index = new Map<string, string>();
  function walk(dir: string) {
    for (const entry of fs
      .readdirSync(dir, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name))) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
        continue;
      }
      const rel = path.relative(path.join(COURSES_ROOT, courseId), abs)
        .split(path.sep)
        .join("/");
      const key = rel.split("/").map(stripNumbering).join("/");
      if (index.has(key)) {
        warn(`归一化路径冲突,仅保留先出现的: ${key} (${index.get(key)}) ←→ ${rel}`);
        continue;
      }
      index.set(key, rel);
    }
  }
  walk(path.join(COURSES_ROOT, courseId));
  return index;
}

/**
 * Second-chance link resolution: map a missed course-relative path through
 * the normalized index and return the URL it should become, or null when
 * nothing matches (the caller keeps the link untouched and reports it).
 *
 * When the full normalized path misses — e.g. the upstream file sat at the
 * repo root but the mirror nested it one level deeper — fall back to the
 * normalized file segment, but only when it is unambiguous.
 */
function fuzzyResolve(
  courseId: string,
  normalizedIndex: Map<string, string>,
  posixRel: string,
  routeByRelPath: Map<string, string>
): string | null {
  const key = posixRel.split("/").map(stripNumbering).join("/");
  let realRel = normalizedIndex.get(key);
  if (!realRel) {
    const fileSegment = key.split("/").pop()!;
    const candidates = [...normalizedIndex.entries()].filter(
      ([candidateKey]) => candidateKey.split("/").pop() === fileSegment
    );
    if (candidates.length !== 1) return null;
    realRel = candidates[0][1];
  }
  const encodedRel = realRel.split("/").map(encodeURIComponent).join("/");
  if (IMAGE_EXTENSIONS.has(path.extname(realRel).toLowerCase())) {
    return `${ASSET_BASE}/course-assets/${courseId}/${encodedRel}`;
  }
  const route = routeByRelPath.get(realRel);
  if (route) return `${ASSET_BASE}${route}`;
  return `${GITHUB_BLOB}/courses/${encodeURIComponent(courseId)}/${encodedRel}`;
}

const MD_LINK_RE = /(!?)\[([^\]]*)\]\(([^)\s]+)([^)]*)\)/g;
const HTML_IMG_RE = /(<img\b[^>]*?\bsrc=)(["'])([^"']+)\2/gi;

/**
 * Rewrite a lesson's relative links against the mirrored course tree:
 *
 * - `../images/2.3.1.png` → `${ASSET_BASE}/course-assets/<id>/images/2.3.1.png`
 * - `../2.4 实验[Lab]/notebook.ipynb` → GitHub blob URL of the mirrored file
 * - `1.2 另一课[Lesson].md` → the lesson's site route
 *
 * Raw HTML `<img src="…">` tags — common in hand-authored books — get the
 * same treatment as markdown image links.
 *
 * Resolution is filesystem-backed — the target is checked to exist inside the
 * course directory — so any upstream relative layout works without hardcoding
 * directory names. Links that resolve outside the course fall back to a
 * GitHub URL; links that miss the mirror get one fuzzy retry through the
 * normalized index (numbering-layout differences) before being reported.
 *
 * Fenced code blocks are skipped entirely: `experts[i](x)` in a Python
 * snippet must not be mistaken for a markdown link.
 */
function rewriteLinks(
  markdown: string,
  courseId: string,
  moduleDirName: string,
  routeByRelPath: Map<string, string>,
  normalizedIndex: Map<string, string>
): string {
  let inFence = false;
  return markdown
    .split("\n")
    .map((line) => {
      if (/^\s{0,3}(?:```|~~~)/.test(line)) {
        inFence = !inFence;
        return line;
      }
      if (inFence) return line;

      const rewritten = line.replace(
        MD_LINK_RE,
        (match, bang: string, text: string, target: string, tail: string) => {
          // Leave anchors, absolute URLs and protocol-relative links untouched.
          if (/^(#|[a-z][a-z0-9+.-]*:|\/\/)/i.test(target)) return match;
          if (target.startsWith("/")) return match;

          const [rawPath, hash = ""] = target.split("#");
          if (!rawPath) return match;
          const { resolved, posixRel, outside } = resolveAgainstModule(
            courseId,
            moduleDirName,
            rawPath
          );

          // Outside the course tree (or the course root itself): link to GitHub.
          if (outside) {
            let decodedPath = rawPath;
            try {
              decodedPath = decodeURIComponent(rawPath);
            } catch {
              // A literal `%` in the path — treat it as-is.
            }
            return `${bang}[${text}](${githubBlobUrl(courseId, moduleDirName, decodedPath.replace(/\\/g, "/"))}${tail})`;
          }

          const encodedRel = posixRel.split("/").map(encodeURIComponent).join("/");
          const ext = path.extname(posixRel).toLowerCase();

          if (IMAGE_EXTENSIONS.has(ext)) {
            if (!fs.existsSync(resolved)) {
              const fuzzy = fuzzyResolve(courseId, normalizedIndex, posixRel, routeByRelPath);
              if (fuzzy) return `${bang}[${text}](${fuzzy}${tail})`;
              warn(`图片不存在,保留原样: ${posixRel} (← ${rawPath})`);
              return match;
            }
            return `${bang}[${text}](${ASSET_BASE}/course-assets/${courseId}/${encodedRel}${tail})`;
          }

          if (ext === ".md") {
            // A link to a sibling lesson: resolve to its route when it is one.
            const route = routeByRelPath.get(posixRel);
            if (route) {
              return `${bang}[${text}](${ASSET_BASE}${route}${hash ? `#${hash}` : ""}${tail})`;
            }
            if (fs.existsSync(resolved)) {
              return `${bang}[${text}](${GITHUB_BLOB}/courses/${encodeURIComponent(courseId)}/${encodedRel}${tail})`;
            }
            const fuzzy = fuzzyResolve(courseId, normalizedIndex, posixRel, routeByRelPath);
            if (fuzzy) {
              return `${bang}[${text}](${fuzzy}${hash ? `#${hash}` : ""}${tail})`;
            }
            warn(`课时交叉链接不存在,保留原样: ${posixRel}`);
            return match;
          }

          // Anything else that exists in the mirror (notebooks, py, csv, db…)
          // gets a GitHub blob link; anything that doesn't is reported.
          if (fs.existsSync(resolved)) {
            return `${bang}[${text}](${GITHUB_BLOB}/courses/${encodeURIComponent(courseId)}/${encodedRel}${tail})`;
          }
          const fuzzy = fuzzyResolve(courseId, normalizedIndex, posixRel, routeByRelPath);
          if (fuzzy) return `${bang}[${text}](${fuzzy}${tail})`;
          warn(`链接目标不存在,保留原样: ${posixRel} (← ${rawPath})`);
          return match;
        }
      );

      // HTML `<img src="…">` — markdown-link syntax doesn't cover these.
      return rewritten.replace(
        HTML_IMG_RE,
        (match, lead: string, quote: string, src: string) => {
          if (/^(#|[a-z][a-z0-9+.-]*:|\/\/)/i.test(src)) return match;
          if (src.startsWith("/")) return match;
          const [rawPath] = src.split("#");
          if (!rawPath) return match;
          const { resolved, posixRel, outside } = resolveAgainstModule(
            courseId,
            moduleDirName,
            rawPath
          );
          if (outside) {
            let decodedPath = rawPath;
            try {
              decodedPath = decodeURIComponent(rawPath);
            } catch {
              // A literal `%` in the path — treat it as-is.
            }
            return `${lead}${quote}${githubBlobUrl(courseId, moduleDirName, decodedPath.replace(/\\/g, "/"))}${quote}`;
          }
          if (!IMAGE_EXTENSIONS.has(path.extname(posixRel).toLowerCase())) {
            warn(`HTML <img> 指向非图片文件,保留原样: ${posixRel}`);
            return match;
          }
          if (!fs.existsSync(resolved)) {
            const fuzzy = fuzzyResolve(courseId, normalizedIndex, posixRel, routeByRelPath);
            if (fuzzy) return `${lead}${quote}${fuzzy}${quote}`;
            warn(`图片不存在,保留原样: ${posixRel} (← ${rawPath})`);
            return match;
          }
          const encodedRel = posixRel.split("/").map(encodeURIComponent).join("/");
          return `${lead}${quote}${ASSET_BASE}/course-assets/${courseId}/${encodedRel}${quote}`;
        }
      );
    })
    .join("\n");
}

// ---------------------------------------------------------------------------
// Assets
// ---------------------------------------------------------------------------

/**
 * Copy every image in the course tree to `public/course-assets/<id>/`,
 * preserving the course-relative path so rewritten links resolve 1:1.
 */
function copyCourseAssets(courseId: string): { count: number; firstRel?: string } {
  const src = path.join(COURSES_ROOT, courseId);
  const dest = path.join(ASSETS_OUT, courseId);
  fs.rmSync(dest, { recursive: true, force: true });

  let count = 0;
  let firstRel: string | undefined;
  function walk(dir: string) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name)
    )) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
        continue;
      }
      if (!IMAGE_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) continue;
      const rel = path.relative(src, abs);
      const target = path.join(dest, rel);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(abs, target);
      if (!firstRel) firstRel = rel.split(path.sep).join("/");
      count += 1;
    }
  }
  walk(src);
  return { count, firstRel };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  console.log("提取 courses/ 内容…");
  console.log(`  仓库根目录: ${REPO_ROOT}`);
  if (ASSET_BASE) console.log(`  basePath: ${ASSET_BASE}`);

  fs.mkdirSync(OUT_DIR, { recursive: true });

  if (!fs.existsSync(COURSES_ROOT)) {
    console.log("  没有 courses/ 目录,写出空索引。");
    fs.writeFileSync(path.join(OUT_DIR, "courses.json"), JSON.stringify({ courses: [] }));
    return;
  }

  const discovered: { id: string; manifest: CourseManifest }[] = [];
  for (const entry of fs.readdirSync(COURSES_ROOT, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const manifestPath = path.join(COURSES_ROOT, entry.name, "course.json");
    if (!fs.existsSync(manifestPath)) {
      warn(`缺少 course.json,已跳过: courses/${entry.name}/`);
      continue;
    }
    discovered.push({
      id: entry.name,
      manifest: JSON.parse(fs.readFileSync(manifestPath, "utf-8")),
    });
  }

  discovered.sort((a, b) => (a.manifest.order ?? 999) - (b.manifest.order ?? 999));

  const courses: Course[] = [];
  for (const { id, manifest } of discovered) {
    const { count: images, firstRel } = copyCourseAssets(id);
    const course = extractCourse(id, manifest);
    const coverRel = manifest.cover ?? firstRel;
    if (coverRel) {
      course.coverUrl = `${ASSET_BASE}/course-assets/${id}/${coverRel.split("/").map(encodeURIComponent).join("/")}`;
    }
    console.log(
      `  ${course.title}: ${course.modules.length} 个模块,${course.stats.lessons} 节课,${course.stats.labs} 个实验,图片 ${images} 张`
    );
    courses.push(course);
  }

  fs.writeFileSync(
    path.join(OUT_DIR, "courses.json"),
    JSON.stringify({ courses }, null, 2)
  );

  if (warnings.length > 0) {
    console.log(`\n⚠ ${warnings.length} 条提示:`);
    for (const message of warnings) console.log(`  - ${message}`);
  } else {
    console.log("  无告警。");
  }
}

main();
