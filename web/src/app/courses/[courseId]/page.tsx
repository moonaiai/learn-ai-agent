import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getCourse, getCourses } from "@/lib/courses";

interface PageProps {
  params: Promise<{ courseId: string }>;
}

export function generateStaticParams() {
  return getCourses().map((course) => ({ courseId: course.id }));
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { courseId } = await params;
  const course = getCourse(courseId);
  if (!course) return {};
  return { title: course.title, description: course.description || undefined };
}

export default async function CoursePage({ params }: PageProps) {
  const { courseId } = await params;
  const course = getCourse(courseId);
  if (!course) notFound();

  const firstLesson = course.ordered.find((lesson) => lesson.kind === "lesson");

  return (
    <>
      <section className="doc-header course-header">
        <div className="eyebrow">
          <Link href="/courses/">系统课程</Link>
          {course.instructor ? ` · ${course.instructor}` : ""}
        </div>
        <h1>
          {course.title}
          {course.subtitle ? <span className="course-subtitle">{course.subtitle}</span> : null}
        </h1>
        {course.description && <p className="doc-summary">{course.description}</p>}
        <div className="meta-row">
          <span className="pill">{course.modules.length} 个模块</span>
          <span className="pill">{course.stats.lessons} 节课</span>
          {course.stats.labs > 0 && <span className="pill">{course.stats.labs} 个实验</span>}
        </div>
        <div className="course-actions">
          {firstLesson && (
            <Link className="course-cta" href={firstLesson.route}>
              从第一课开始 →
            </Link>
          )}
          {course.video && (
            <a className="source-link" href={course.video} target="_blank" rel="noreferrer">
              原课程视频 ↗
            </a>
          )}
          {course.source && (
            <a className="source-link" href={course.source} target="_blank" rel="noreferrer">
              内容来源仓库 ↗
            </a>
          )}
        </div>
      </section>

      <section className="syllabus">
        {course.modules.map((module) => (
          <div key={module.number} className="syllabus-module">
            <h2>
              <span className="syllabus-num">M{module.number}</span>
              {module.title}
              {module.titleEn && <small>{module.titleEn}</small>}
            </h2>
            <ol className="syllabus-lessons">
              {module.lessons.map((lesson) => (
                <li key={lesson.number}>
                  {lesson.kind === "lab" ? (
                    <a href={lesson.githubUrl} target="_blank" rel="noreferrer">
                      <span className="syllabus-num">{lesson.number}</span>
                      <span className="syllabus-title">{lesson.title}</span>
                      <span className="lab-badge">实验 ↗</span>
                    </a>
                  ) : (
                    <Link href={lesson.route}>
                      <span className="syllabus-num">{lesson.number}</span>
                      <span className="syllabus-title">{lesson.title}</span>
                      {lesson.titleEn && <small>{lesson.titleEn}</small>}
                    </Link>
                  )}
                </li>
              ))}
            </ol>
          </div>
        ))}
      </section>
    </>
  );
}
