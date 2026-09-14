import type { Course, CourseAttribution } from "@/lib/types";

/**
 * 出处与授权说明 — mirrored courses belong to their original authors; this
 * site only aggregates and re-renders them. Full block on the course page,
 * compact footer line on lesson pages.
 */

function sourceUrl(attribution: CourseAttribution, course: Course): string | undefined {
  return attribution.url ?? course.source;
}

function fullAttribution(attribution: CourseAttribution, course: Course) {
  const origin = sourceUrl(attribution, course);
  return (
    <aside className="course-attribution">
      <div className="attribution-head">内容出处 · Attribution</div>
      <p>
        本课程内容来自
        {attribution.originalTitle ? (
          <>
            「<strong>{attribution.originalTitle}</strong>」
          </>
        ) : (
          "上游开源项目"
        )}
        {attribution.authors && attribution.authors.length > 0 && (
          <>
            ，原作者/出品方：
            <strong>{attribution.authors.join("、")}</strong>
          </>
        )}
        {attribution.license && (
          <>
            ，以{" "}
            {attribution.licenseUrl ? (
              <a href={attribution.licenseUrl} target="_blank" rel="noreferrer">
                {attribution.license}
              </a>
            ) : (
              attribution.license
            )}{" "}
            协议发布
          </>
        )}
        。
      </p>
      {attribution.note && <p className="attribution-note">{attribution.note}</p>}
      <p className="attribution-disclaimer">
        本站仅做汇总与二次渲染（目录重组、格式适配与站内互链），不改动原作内容；
        版权归原作者所有，学习之外的使用请遵循原作许可。
      </p>
      {origin && (
        <p className="attribution-links">
          <a href={origin} target="_blank" rel="noreferrer">
            查看原作仓库 ↗
          </a>
          {attribution.licenseUrl && (
            <a href={attribution.licenseUrl} target="_blank" rel="noreferrer">
              {attribution.license} ↗
            </a>
          )}
        </p>
      )}
    </aside>
  );
}

function compactAttribution(attribution: CourseAttribution, course: Course) {
  const origin = sourceUrl(attribution, course);
  return (
    <p className="course-attribution lesson-attribution">
      本文出自
      {attribution.originalTitle ? (
        <>
          「<strong>{attribution.originalTitle}</strong>」
        </>
      ) : (
        "上游开源项目"
      )}
      {attribution.authors && attribution.authors.length > 0 && (
        <>
          （{attribution.authors.join("、")}）
        </>
      )}
      {attribution.license && <>，以 {attribution.license} 协议发布</>}
      ；本站仅做汇总与二次渲染，版权归原作者所有。
      {origin && (
        <>
          {" "}
          <a href={origin} target="_blank" rel="noreferrer">
            查看原作 ↗
          </a>
        </>
      )}
    </p>
  );
}

/**
 * `variant="full"` for the course home page, `variant="compact"` for lesson
 * footers. Renders nothing when the manifest carries no attribution — but
 * every mirrored course is expected to declare one.
 */
export function CourseAttributionNote({
  course,
  variant = "full",
}: {
  course: Course;
  variant?: "full" | "compact";
}) {
  if (!course.attribution) return null;
  return variant === "full"
    ? fullAttribution(course.attribution, course)
    : compactAttribution(course.attribution, course);
}
