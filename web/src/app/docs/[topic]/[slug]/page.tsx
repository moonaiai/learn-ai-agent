import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getAllDocs, getDoc, getNeighbours } from "@/lib/docs";
import { DocContent } from "@/components/doc-content";
import { DocToc } from "@/components/doc-toc";
import { PdfViewer } from "@/components/pdf-viewer";
import { PrevNext } from "@/components/prev-next";

interface PageProps {
  params: Promise<{ topic: string; slug: string }>;
}

export function generateStaticParams() {
  return getAllDocs().map((doc) => ({ topic: doc.topic, slug: doc.slug }));
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { topic, slug } = await params;
  const doc = getDoc(topic, slug);
  if (!doc) return {};
  return {
    title: doc.title,
    description: doc.summary || undefined,
  };
}

export default async function DocPage({ params }: PageProps) {
  const { topic, slug } = await params;
  const doc = getDoc(topic, slug);
  if (!doc) notFound();

  const { prev, next } = getNeighbours(topic, slug);

  return (
    <>
      <section className="doc-header">
        <div className="eyebrow">{doc.topicLabel}</div>
        <h1>{doc.title}</h1>
        {doc.summary && <p className="doc-summary">{doc.summary}</p>}
        {doc.sourcesHtml && (
          <div
            className="doc-sources"
            dangerouslySetInnerHTML={{ __html: doc.sourcesHtml }}
          />
        )}
        <a
          className="source-link"
          href={doc.githubUrl}
          target="_blank"
          rel="noreferrer"
        >
          在 GitHub 上查看源文件：{doc.sourcePath}
        </a>
      </section>

      {doc.kind === "pdf" ? (
        <PdfViewer
          url={doc.pdfUrl!}
          title={doc.title}
          bytes={doc.bytes}
        />
      ) : (
        <div className="doc-layout">
          <DocContent html={doc.html ?? ""} />
          <DocToc headings={doc.headings} />
        </div>
      )}

      <PrevNext prev={prev} next={next} />
    </>
  );
}
