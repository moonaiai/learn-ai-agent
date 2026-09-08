import type { Metadata } from "next";
import Link from "next/link";
import { getCourses } from "@/lib/courses";

export const metadata: Metadata = {
  title: "系统课程",
  description: "有完整章节结构的系列课程,按模块与课时顺序组织。",
};

export default function CoursesPage() {
  const courses = getCourses();

  return (
    <>
      <section className="hero" style={{ ["--site-mark" as string]: '"COURSE"' }}>
        <div className="eyebrow">Courses</div>
        <h1>系统课程</h1>
        <p className="lead">
          与零散文档不同,这里的课程有完整的章节结构:按模块与课时顺序组织,
          配套实验与原课程链接,适合从头学到尾。
        </p>
        <div className="meta-row">
          <span className="pill">{courses.length} 门课程</span>
          <span className="pill">
            {courses.reduce((sum, course) => sum + course.stats.lessons, 0)} 节课
          </span>
          <span className="pill">持续更新</span>
        </div>
      </section>

      <section>
        <div className="course-list">
          {courses.map((course, index) => (
            <Link
              key={course.id}
              className="track-card course-row"
              href={`/courses/${course.id}/`}
            >
              <div className="track-body">
                <div className="track-topline">
                  <span className="track-num">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <span className="track-count">
                    {course.stats.lessons} 节课
                    {course.stats.labs > 0 ? ` · ${course.stats.labs} 个实验` : ""}
                  </span>
                </div>
                <h3>
                  {course.title}
                  {course.subtitle && (
                    <span className="course-subtitle">{course.subtitle}</span>
                  )}
                </h3>
                <p>{course.description}</p>
                <span className="state">
                  {course.instructor ? `${course.instructor} · ` : ""}
                  {course.modules.length} 个模块 →
                </span>
              </div>
            </Link>
          ))}
        </div>
      </section>
    </>
  );
}
