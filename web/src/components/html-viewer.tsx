"use client";

import { useRef, useState } from "react";
import { formatBytes } from "@/lib/docs";

interface HtmlViewerProps {
  /** Public URL with the basePath already applied by the extractor. */
  url: string;
  title: string;
  bytes?: number;
}

/**
 * Embeds a standalone HTML document (slide deck, interactive demo) in an iframe.
 *
 * These pages arrive self-contained: their own `<style>`, their own scripts, and
 * often `html, body { overflow: hidden }` plus global key handlers because they
 * expect to own the viewport. An iframe is what keeps that working without their
 * CSS leaking into the site shell — inlining the markup would break both.
 *
 * Two affordances the PDF viewer doesn't need:
 *   - Fullscreen, because a 1920×1080 deck scaled into a column is unreadable.
 *   - The iframe is only focusable after a click; decks bind ArrowLeft/Right on
 *     their own `document`, and those events don't reach it until it has focus.
 */
export function HtmlViewer({ url, title, bytes }: HtmlViewerProps) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const [expanded, setExpanded] = useState(false);

  function requestFullscreen() {
    const frame = frameRef.current;
    if (!frame) return;
    // Safari < 16.4 only exposes the webkit-prefixed form.
    const request =
      frame.requestFullscreen ??
      (frame as unknown as { webkitRequestFullscreen?: () => Promise<void> })
        .webkitRequestFullscreen;
    request?.call(frame);
  }

  return (
    <div className={`embed-card${expanded ? " expanded" : ""}`}>
      <div className="embed-toolbar">
        <span>
          {title}
          {bytes ? ` · HTML ${formatBytes(bytes)}` : ""}
        </span>
        <div className="embed-actions">
          <button type="button" onClick={() => setExpanded((value) => !value)}>
            {expanded ? "还原高度" : "放大高度"}
          </button>
          <button type="button" onClick={requestFullscreen}>
            全屏
          </button>
          <a href={url} target="_blank" rel="noreferrer">
            新窗口打开
          </a>
        </div>
      </div>

      <iframe
        ref={frameRef}
        className="embed-frame"
        src={url}
        title={title}
        loading="lazy"
        // Scripts are needed (these decks are interactive) but the documents are
        // first-party, checked into docs/. same-origin is withheld so the frame
        // can't reach this site's storage or DOM.
        sandbox="allow-scripts allow-popups allow-forms"
        allowFullScreen
      />

      <p className="embed-hint">
        交互页面已内嵌显示。点击页面内部后可使用方向键翻页；也可
        <a href={url} target="_blank" rel="noreferrer">
          在新窗口打开
        </a>
        获得完整体验。
      </p>
    </div>
  );
}
