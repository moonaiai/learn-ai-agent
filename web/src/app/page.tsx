import { getNav } from "@/lib/docs";
import { DocCard } from "@/components/doc-card";

export default function HomePage() {
  const nav = getNav();
  const { markdown, pdf, html, categories } = nav.stats;

  return (
    <>
      <section className="hero" style={{ ["--site-mark" as string]: '"AGENT"' }}>
        <div className="eyebrow">Engineering Notes</div>
        <h1>面向工程实践的 AI Agent 知识库</h1>
        <p className="lead">
          少讲概念口号，多讲设计边界、实现结构、取舍依据和落地检查项。从 Transformer
          与采样参数等底层原理，到 Agent 控制流、上下文工程、评测与生产可靠性。
        </p>
        <div className="meta-row">
          <span className="pill">{markdown} 篇文档</span>
          <span className="pill">{pdf} 份 PDF</span>
          {html > 0 && <span className="pill">{html} 个在线演示</span>}
          <span className="pill">{categories} 个主题分类</span>
          <span className="pill">中文 · 持续更新</span>
        </div>
      </section>

      {nav.categories.map((category) => (
        <section key={category.id}>
          <div className="section-heading">
            <div>
              <h2 id={category.id}>{category.label}</h2>
              <p>{category.blurb}</p>
            </div>
            <p>{category.docs.length} 篇</p>
          </div>
          <div className="doc-grid">
            {category.docs.map((doc) => (
              <DocCard key={doc.route} doc={doc} />
            ))}
          </div>
        </section>
      ))}
    </>
  );
}
