import Link from "next/link";
import type { Course } from "@/lib/types";

/**
 * Sticky course sidebar for lesson pages: the full syllabus with the current
 * lesson highlighted. Replaces the per-page TOC here — when following a
 * course, "where am I in the curriculum" beats "where am I on this page".
 */
export function CourseNav({
  course,
  currentSlug,
}: {
  course: Course;
  currentSlug: string;
}) {
  return (
    <nav className="toc course-toc">
      <strong>
        <Link href={`/courses/${course.id}/`}>{course.title}</Link>
      </strong>
      {course.modules.map((module) => (
        <div key={module.number} className="course-toc-module">
          <span className="course-toc-module-title">
            M{module.number} {module.title}
          </span>
          {module.lessons.map((lesson) =>
            lesson.kind === "lab" ? (
              <a
                key={lesson.number}
                className="sub lab"
                href={lesson.githubUrl}
                target="_blank"
                rel="noreferrer"
              >
                <span className="toc-num">{lesson.number}</span>
                {lesson.title}
                <span className="lab-badge">实验</span>
              </a>
            ) : (
              <Link
                key={lesson.number}
                className={`sub${lesson.slug === currentSlug ? " active" : ""}`}
                href={lesson.route}
              >
                <span className="toc-num">{lesson.number}</span>
                {lesson.title}
              </Link>
            )
          )}
        </div>
      ))}
    </nav>
  );
}
