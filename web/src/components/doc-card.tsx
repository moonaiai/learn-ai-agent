import Link from "next/link";
import type { NavEntry } from "@/lib/types";
import { formatBytes } from "@/lib/docs";

export function DocCard({ doc }: { doc: NavEntry }) {
  return (
    <Link className="doc-card" href={doc.route}>
      <small>
        {doc.topicLabel}
        {doc.kind === "pdf" && doc.bytes
          ? ` · PDF ${formatBytes(doc.bytes)}`
          : ""}
      </small>
      <h3>{doc.title}</h3>
      <p>{doc.summary}</p>
      <span className={`state${doc.kind === "pdf" ? " badge-pdf" : ""}`}>
        {doc.kind === "pdf" ? "查看 PDF →" : "开始阅读 →"}
      </span>
    </Link>
  );
}
