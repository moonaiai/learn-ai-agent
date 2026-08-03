import docsJson from "@/data/generated/docs.json";
import navJson from "@/data/generated/nav.json";
import type { DocEntry, NavEntry, NavIndex } from "./types";

const docs = docsJson as DocEntry[];
const nav = navJson as NavIndex;

export function getNav(): NavIndex {
  return nav;
}

export function getAllDocs(): DocEntry[] {
  return docs;
}

export function getDoc(topic: string, slug: string): DocEntry | undefined {
  return docs.find((doc) => doc.topic === topic && doc.slug === slug);
}

/**
 * Previous / next document in category order — the same order the home page
 * lists them in, so the arrows follow the intended reading sequence.
 */
export function getNeighbours(topic: string, slug: string): {
  prev?: NavEntry;
  next?: NavEntry;
} {
  const index = nav.ordered.findIndex(
    (doc) => doc.topic === topic && doc.slug === slug
  );
  if (index === -1) return {};
  return {
    prev: index > 0 ? nav.ordered[index - 1] : undefined,
    next: index < nav.ordered.length - 1 ? nav.ordered[index + 1] : undefined,
  };
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
