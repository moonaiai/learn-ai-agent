import Link from "next/link";
import type { NavCategory } from "@/lib/types";

/**
 * A track — a curated learning unit on the home page. Rendered as a text card
 * with a number, a count and a blurb; courses attached to the track surface as
 * a small flag. The directory is a single scannable list.
 */
export function TrackCard({
  track,
  index,
  docWord = "篇文档",
}: {
  track: NavCategory;
  /** Zero-based position — drives the numbering. */
  index: number;
  docWord?: string;
}) {
  const count = `${track.docs.length} ${docWord}`;
  const number = String(index + 1).padStart(2, "0");

  return (
    <Link className="track-card compact" href={`/tracks/${track.id}/`}>
      <span className="track-num">{number}</span>
      <span className="track-compact-main">
        <span className="track-compact-title">
          {track.label}
          {track.courses.length > 0 && (
            <span className="track-flag">含 {track.courses.length} 门课程</span>
          )}
        </span>
        <span className="track-compact-blurb">{track.blurb}</span>
      </span>
      <span className="track-count">{count}</span>
      <span className="track-arrow">→</span>
    </Link>
  );
}
