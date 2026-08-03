"use client";

import { useEffect, useState } from "react";

type Theme = "midnight" | "parchment";

const STORAGE_KEY = "docs-theme";
const LABELS: Record<Theme, string> = {
  midnight: "深色",
  parchment: "浅色",
};

/**
 * Toggles between the two token sets by setting `data-theme` on <html>.
 * The initial value is applied by the inline script in layout.tsx (before
 * first paint); this component only mirrors and updates it.
 */
export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>("midnight");

  useEffect(() => {
    const current = document.documentElement.getAttribute("data-theme");
    setTheme(current === "parchment" ? "parchment" : "midnight");
  }, []);

  function toggle() {
    const next: Theme = theme === "midnight" ? "parchment" : "midnight";
    setTheme(next);
    if (next === "midnight") {
      document.documentElement.removeAttribute("data-theme");
    } else {
      document.documentElement.setAttribute("data-theme", next);
    }
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Private browsing / storage disabled — the toggle still works for the
      // current page, it just won't persist.
    }
  }

  const nextLabel = theme === "midnight" ? LABELS.parchment : LABELS.midnight;

  return (
    <button
      className="theme-toggle"
      type="button"
      onClick={toggle}
      aria-label={`切换到${nextLabel}主题`}
    >
      {nextLabel}
    </button>
  );
}
