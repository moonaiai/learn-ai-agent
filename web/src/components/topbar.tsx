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
          <Link href="/">文档目录</Link>
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
