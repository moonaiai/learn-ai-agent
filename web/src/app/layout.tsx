import type { Metadata } from "next";
import { Topbar } from "@/components/topbar";
import "katex/dist/katex.min.css";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Learn AI Agent",
    template: "%s | Learn AI Agent",
  },
  description:
    "面向 AI Agent 工程实践的中文知识库：Agent 设计原则、上下文工程、评测与可靠性、大模型基础原理。",
};

// Applied before first paint so the chosen theme doesn't flash.
const THEME_BOOTSTRAP = `(function(){try{var t=localStorage.getItem('docs-theme');if(t==='parchment'){document.documentElement.setAttribute('data-theme','parchment');}}catch(e){}})();`;

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="zh-CN" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP }} />
      </head>
      <body>
        <div className="site-shell">
          <Topbar />
          {children}
          <footer className="site-footer">
            Learn AI Agent · 面向 AI Agent 工程实践的中文知识库
          </footer>
        </div>
      </body>
    </html>
  );
}
