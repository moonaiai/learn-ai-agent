import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getNav } from "@/lib/docs";
import { DocCard } from "@/components/doc-card";

interface PageProps {
  params: Promise<{ trackId: string }>;
}

export function generateStaticParams() {
  return getNav().categories.map((category) => ({ trackId: category.id }));
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { trackId } = await params;
  const category = getNav().categories.find((entry) => entry.id === trackId);
  if (!category) return {};
  return { title: category.label, description: category.blurb || undefined };
}

export default async function TrackPage({ params }: PageProps) {
  const { trackId } = await params;
  const category = getNav().categories.find((entry) => entry.id === trackId);
  if (!category) notFound();

  return (
    <>
      <section className="doc-header">
        <div className="eyebrow">
          <Link href="/">学习专题</Link>
        </div>
        <h1>{category.label}</h1>
        {category.blurb && <p className="doc-summary">{category.blurb}</p>}
        <div className="meta-row">
          <span className="pill">{category.docs.length} 篇</span>
          {category.courses.length > 0 && (
            <span className="pill">{category.courses.length} 门课程</span>
          )}
        </div>
      </section>

      {category.courses.length > 0 && (
        <section>
          <div className="section-heading">
            <div>
              <h2>相关课程</h2>
              <p>本专题对应的系统课程,按模块与课时顺序学习。</p>
            </div>
          </div>
          <div className="doc-grid">
            {category.courses.map((course) => (
              <Link key={course.id} className="doc-card course-card" href={`/courses/${course.id}/`}>
                <small>系统课程</small>
                <h3>{course.title}</h3>
                <span className="state">进入课程 →</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      <section>
        <div className="section-heading">
          <div>
            <h2>文档</h2>
            <p>{category.docs.length} 篇,按主题排列。</p>
          </div>
        </div>
        <div className="doc-grid">
          {category.docs.map((doc) => (
            <DocCard key={doc.route} doc={doc} />
          ))}
        </div>
      </section>
    </>
  );
}
