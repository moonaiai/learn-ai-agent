import Link from "next/link";
import { ThemeToggle } from "./theme-toggle";

export function Topbar() {
  return (
    <header className="topbar">
      <Link className="brand" href="/">
        Learn AI Agent
      </Link>
      <div className="topbar-right">
        <nav>
          <Link href="/">学习专题</Link>
          <Link href="/courses/">系统课程</Link>
          <a
            href="https://github.com/moonaiai/learn-ai-agent"
            target="_blank"
            rel="noreferrer"
          >
            GitHub
          </a>
        </nav>
        <ThemeToggle />
      </div>
    </header>
  );
}
