import Link from "next/link";
import type { NavEntry } from "@/lib/types";
import { formatBytes } from "@/lib/docs";

/** Size-badge prefix and call-to-action, per document kind. */
const KIND_LABELS: Record<NavEntry["kind"], { badge: string; cta: string }> = {
  md: { badge: "", cta: "开始阅读 →" },
  pdf: { badge: "PDF", cta: "查看 PDF →" },
  html: { badge: "HTML", cta: "打开演示 →" },
};

export function DocCard({ doc }: { doc: NavEntry }) {
  const { badge, cta } = KIND_LABELS[doc.kind];

  return (
    <Link className="doc-card" href={doc.route}>
      <small>
        {doc.topicLabel}
        {badge && doc.bytes ? ` · ${badge} ${formatBytes(doc.bytes)}` : ""}
      </small>
      <h3>{doc.title}</h3>
      <p>{doc.summary}</p>
      <span className={`state${doc.kind === "md" ? "" : ` badge-${doc.kind}`}`}>
        {cta}
      </span>
    </Link>
  );
}
