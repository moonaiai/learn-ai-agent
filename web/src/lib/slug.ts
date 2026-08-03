import * as crypto from "crypto";

/**
 * Slugify a path segment for use in a URL.
 *
 * Doc filenames in this repo mix ASCII, CJK, spaces and em-dashes (e.g.
 * "企业级AI Agent落地挑战 — 从Demo到Production的鸿沟.pdf"). CJK characters are
 * dropped rather than percent-encoded so the resulting URLs stay readable and
 * portable; callers must keep the original text around for display.
 *
 * Returns an empty string when nothing usable survives — callers should fall
 * back to a hash via {@link uniqueSlug}.
 */
export function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

function shortHash(input: string): string {
  return crypto.createHash("sha1").update(input).digest("hex").slice(0, 6);
}

/**
 * Slugify `input`, guaranteeing a non-empty result that is unique within
 * `taken`. Falls back to (or appends) a short content hash derived from
 * `hashSeed` so the slug stays stable across builds.
 *
 * Mutates `taken` by adding the returned slug.
 */
export function uniqueSlug(
  input: string,
  hashSeed: string,
  taken: Set<string>
): string {
  const base = slugify(input);
  const candidate = base || `doc-${shortHash(hashSeed)}`;

  if (!taken.has(candidate)) {
    taken.add(candidate);
    return candidate;
  }

  const withHash = `${candidate}-${shortHash(hashSeed)}`;
  taken.add(withHash);
  return withHash;
}
