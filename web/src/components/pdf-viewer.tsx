"use client";

import { useEffect, useRef, useState } from "react";
import { formatBytes } from "@/lib/docs";

interface PdfViewerProps {
  /** Public URL with the basePath already applied by the extractor. */
  url: string;
  title: string;
  bytes?: number;
}

/**
 * Embeds a PDF in an <object>, falling back to a download card when the browser
 * has no PDF plugin.
 *
 * `<object>` only shows its children when the resource fails to *load* — a
 * browser that loads the PDF but can't render it (common on mobile) leaves a
 * silent blank box instead. So the fallback is driven by a capability check on
 * `navigator.mimeTypes` rather than by the element itself.
 *
 * The URL is baked at build time rather than composed on the client, so it stays
 * correct under both local dev (no basePath) and the GitHub Pages project path.
 */
export function PdfViewer({ url, title, bytes }: PdfViewerProps) {
  // Assume support during SSR so the frame is in the static HTML; the effect
  // corrects it on browsers that can't render PDFs inline.
  const [canEmbed, setCanEmbed] = useState(true);
  const objectRef = useRef<HTMLObjectElement>(null);

  useEffect(() => {
    const mimeTypes = navigator.mimeTypes as unknown as
      | Record<string, unknown>
      | undefined;
    const hasPdfMime = Boolean(
      mimeTypes &&
        (mimeTypes["application/pdf"] || mimeTypes["text/pdf"])
    );
    // Chrome/Firefox/Safari on desktop all report a pdf mime type. Most mobile
    // browsers don't, and would otherwise render an empty box.
    setCanEmbed(hasPdfMime);
  }, []);

  return (
    <div className="pdf-card">
      <div className="pdf-toolbar">
        <span>
          {title}
          {bytes ? ` · ${formatBytes(bytes)}` : ""}
        </span>
        <div className="pdf-actions">
          <a href={url} target="_blank" rel="noreferrer">
            新窗口打开
          </a>
          <a href={url} download>
            下载
          </a>
        </div>
      </div>

      {canEmbed && (
        <object
          ref={objectRef}
          className="pdf-frame"
          data={url}
          type="application/pdf"
        >
          <iframe className="pdf-frame" src={url} title={title} />
        </object>
      )}

      <div className={`pdf-fallback${canEmbed ? "" : " show"}`}>
        当前浏览器无法内嵌显示 PDF，请
        <a href={url} download>
          下载
        </a>
        或
        <a href={url} target="_blank" rel="noreferrer">
          在新窗口打开
        </a>
        阅读。
      </div>
    </div>
  );
}
