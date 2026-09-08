import { getNav } from "@/lib/docs";
import { getCourses } from "@/lib/courses";
import { TrackCard } from "@/components/track-card";

export default function HomePage() {
  const nav = getNav();
  const courses = getCourses();
  const { markdown, pdf, html } = nav.stats;
  const trackCount = nav.categories.length;

  return (
    <>
      <section className="hero" style={{ ["--site-mark" as string]: '"AGENT"' }}>
        <div className="eyebrow">Engineering Notes</div>
        <h1>面向工程实践的 AI Agent 知识库</h1>
        <p className="lead">
          少讲概念口号，多讲设计边界、实现结构、取舍依据和落地检查项。按专题
          组织——从 Transformer 与采样等底层原理，到 Agent 控制流、上下文工程、
          评测与生产可靠性，配合系统课程从头学到尾。
        </p>
        <div className="meta-row">
          <span className="pill">{trackCount} 个学习专题</span>
          <span className="pill">{courses.length} 门系统课程</span>
          <span className="pill">{markdown} 篇文档</span>
          <span className="pill">{pdf} 份 PDF</span>
          {html > 0 && <span className="pill">{html} 个在线演示</span>}
          <span className="pill">中文 · 持续更新</span>
        </div>
      </section>

      <section>
        <div className="section-heading">
          <div>
            <h2 id="tracks">学习专题</h2>
            <p>
              把零散资料按方向收拢成可进入的专题：每个专题有导览、文档与对应课程。
              想系统学就从含课程的专题开始。
            </p>
          </div>
          <p>{trackCount} 个</p>
        </div>

        <div className="track-list">
          {nav.categories.map((category, index) => (
            <TrackCard key={category.id} track={category} index={index} />
          ))}
        </div>
      </section>
    </>
  );
}
