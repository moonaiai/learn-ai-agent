"use client";

import { useEffect, useRef } from "react";

/**
 * Renders the build-time HTML and wires up the copy buttons that
 * `postProcessHtml` injected into each code card's toolbar.
 */
export function DocContent({ html }: { html: string }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const timers: ReturnType<typeof setTimeout>[] = [];

    function onClick(event: MouseEvent) {
      const button = (event.target as HTMLElement).closest<HTMLButtonElement>(
        "button[data-copy]"
      );
      if (!button) return;

      const code = button
        .closest(".code-card")
        ?.querySelector("code")?.textContent;
      if (!code) return;

      navigator.clipboard.writeText(code).then(
        () => {
          button.textContent = "已复制";
          timers.push(setTimeout(() => (button.textContent = "复制"), 1600));
        },
        () => {
          button.textContent = "复制失败";
          timers.push(setTimeout(() => (button.textContent = "复制"), 1600));
        }
      );
    }

    container.addEventListener("click", onClick);
    return () => {
      container.removeEventListener("click", onClick);
      for (const timer of timers) clearTimeout(timer);
    };
  }, [html]);

  return (
    <div
      ref={containerRef}
      className="doc-content"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
