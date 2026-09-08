import coursesJson from "@/data/generated/courses.json";
import type { Course, CourseLesson } from "./types";

const { courses } = coursesJson as { courses: Course[] };

export function getCourses(): Course[] {
  return courses;
}

export function getCourse(id: string): Course | undefined {
  return courses.find((course) => course.id === id);
}

export function getLesson(
  courseId: string,
  slug: string
): { course: Course; lesson: CourseLesson } | undefined {
  const course = getCourse(courseId);
  const lesson = course?.ordered.find(
    (entry) => entry.kind === "lesson" && entry.slug === slug
  );
  if (!course || !lesson) return undefined;
  return { course, lesson };
}

/**
 * Previous / next *lesson* in curriculum order. Labs have no page and are
 * skipped, so the arrows always land on readable content.
 */
export function getLessonNeighbours(
  course: Course,
  slug: string
): { prev?: CourseLesson; next?: CourseLesson } {
  const readable = course.ordered.filter((entry) => entry.kind === "lesson");
  const index = readable.findIndex((entry) => entry.slug === slug);
  if (index === -1) return {};
  return {
    prev: index > 0 ? readable[index - 1] : undefined,
    next: index < readable.length - 1 ? readable[index + 1] : undefined,
  };
}
