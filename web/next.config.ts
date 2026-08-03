import type { NextConfig } from "next";

// basePath is only set for the GitHub Pages deployment (project site served at
// https://moonaiai.github.io/learn-ai-agent/). Local dev leaves it empty; the
// deploy workflow sets NEXT_BASE_PATH=/learn-ai-agent.
const basePath = process.env.NEXT_BASE_PATH ?? "";

const nextConfig: NextConfig = {
  output: "export",
  basePath: basePath || undefined,
  assetPrefix: basePath || undefined,
  images: { unoptimized: true },
  trailingSlash: true,
};

export default nextConfig;
