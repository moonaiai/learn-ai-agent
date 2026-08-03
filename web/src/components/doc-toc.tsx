"use client";

import { useEffect, useState } from "react";
import type { Heading } from "@/lib/types";

/**
 * Sticky table of contents. Highlights the heading currently in view using an
 * IntersectionObserver over the rendered h2/h3 anchors.
 */
export function DocToc({ headings }: { headings: Heading[] }) {
  const [activeId, setActiveId] = useState<string>("");

  useEffect(() => {
    if (headings.length === 0) return;

    const elements = headings
      .map((heading) => document.getElementById(heading.id))
      .filter((element): element is HTMLElement => element !== null);

    if (elements.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible[0]) setActiveId(visible[0].target.id);
      },
      // Bias the active band towards the top of the viewport so the highlight
      // tracks what the reader is actually looking at.
      { rootMargin: "-10% 0px -70% 0px", threshold: 0 }
    );

    for (const element of elements) observer.observe(element);
    return () => observer.disconnect();
  }, [headings]);

  if (headings.length === 0) return null;

  let counter = 0;

  return (
    <aside className="toc">
      <strong>目录</strong>
      {headings.map((heading) => {
        if (heading.depth === 2) counter += 1;
        return (
          <a
            key={heading.id}
            href={`#${heading.id}`}
            className={[
              heading.depth === 3 ? "sub" : "",
              heading.id === activeId ? "active" : "",
            ]
              .filter(Boolean)
              .join(" ")}
          >
            {heading.depth === 2 && (
              <span className="toc-num">
                {String(counter).padStart(2, "0")}
              </span>
            )}
            {heading.text}
          </a>
        );
      })}
    </aside>
  );
}
