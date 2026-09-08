import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getCourse, getCourses, getLesson, getLessonNeighbours } from "@/lib/courses";
import { CourseNav } from "@/components/course-nav";
import { DocContent } from "@/components/doc-content";
import { PrevNext } from "@/components/prev-next";

interface PageProps {
  params: Promise<{ courseId: string; lesson: string }>;
}

export function generateStaticParams() {
  return getCourses().flatMap((course) =>
    course.ordered
      .filter((lesson) => lesson.kind === "lesson")
      .map((lesson) => ({ courseId: course.id, lesson: lesson.slug }))
  );
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { courseId, lesson } = await params;
  const found = getLesson(courseId, lesson);
  if (!found) return {};
  return {
    title: `${found.lesson.number} ${found.lesson.title}`,
    description: `${found.course.title} · 第 ${found.lesson.number} 节`,
  };
}

export default async function LessonPage({ params }: PageProps) {
  const { courseId, lesson } = await params;
  const found = getLesson(courseId, lesson);
  if (!found) notFound();

  const { course, lesson: entry } = found;
  const { prev, next } = getLessonNeighbours(course, entry.slug);

  return (
    <>
      <section className="doc-header">
        <div className="eyebrow">
          <Link href={`/courses/${course.id}/`}>{course.title}</Link>
          {` · 第 ${entry.number} 节`}
        </div>
        <h1>
          {entry.title}
          {entry.titleEn && <span className="course-subtitle">{entry.titleEn}</span>}
        </h1>
        {entry.githubUrl && (
          <a
            className="source-link"
            href={entry.githubUrl}
            target="_blank"
            rel="noreferrer"
          >
            在 GitHub 上查看源文件
          </a>
        )}
      </section>

      <div className="doc-layout">
        <DocContent html={entry.html ?? ""} />
        <CourseNav course={course} currentSlug={entry.slug} />
      </div>

      <PrevNext prev={prev} next={next} />
    </>
  );
}
