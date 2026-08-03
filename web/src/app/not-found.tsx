import Link from "next/link";

export default function NotFound() {
  return (
    <section className="hero" style={{ ["--site-mark" as string]: '"404"' }}>
      <div className="eyebrow">404</div>
      <h1>没有找到这个页面</h1>
      <p className="lead">
        链接可能已经失效，或者文档被移动到了其他主题目录下。
      </p>
      <div className="meta-row">
        <Link className="pill" href="/">
          返回文档目录
        </Link>
      </div>
    </section>
  );
}
