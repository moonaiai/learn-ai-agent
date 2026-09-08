import Link from "next/link";

/** Anything with a site route and a display title — docs and course lessons. */
interface NavTarget {
  route: string;
  title: string;
}

export function PrevNext({
  prev,
  next,
}: {
  prev?: NavTarget;
  next?: NavTarget;
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
