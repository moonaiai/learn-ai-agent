import Link from "next/link";
import type { NavEntry } from "@/lib/types";

export function PrevNext({
  prev,
  next,
}: {
  prev?: NavEntry;
  next?: NavEntry;
}) {
  if (!prev && !next) return null;

  return (
    <nav className="doc-nav">
      {prev && (
        <Link className="prev" href={prev.route}>
          <small>← 上一篇</small>
          <span>{prev.title}</span>
        </Link>
      )}
      {next && (
        <Link className="next" href={next.route}>
          <small>下一篇 →</small>
          <span>{next.title}</span>
        </Link>
      )}
    </nav>
  );
}
