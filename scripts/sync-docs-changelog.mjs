import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(repositoryRoot, "CHANGELOG.md");
const destinations = [
  {
    path: path.join(repositoryRoot, "docs", "changelog.md"),
    title: "Changelog",
    description: "Winenv version changes and release history",
    introduction: "This page is generated from the root `CHANGELOG.md` during every documentation build. It uses the same commit-derived history as GitHub Releases.",
  },
  {
    path: path.join(repositoryRoot, "docs", "zh", "changelog.md"),
    title: "更新日志",
    description: "Winenv 的版本变化与发布记录",
    introduction: "此页面由根目录的 `CHANGELOG.md` 在每次文档构建时自动生成，与 GitHub Release 使用同一份提交记录。发布条目保留自动生成的英文原文，避免维护两份可能不一致的版本历史。",
  },
];

const source = await readFile(sourcePath, "utf8");
const body = source
  .trim()
  .split("\n")
  .map((line) => line.replace(/^(#{1,5})(\s+)/, "#$1$2"))
  .join("\n");

for (const destination of destinations) {
  const page = `---
title: ${destination.title}
description: ${destination.description}
editLink: false
outline: [2, 4]
---

# ${destination.title}

${destination.introduction}

${body}
`;

  await writeFile(destination.path, page, "utf8");
  console.log(`Synced ${path.relative(repositoryRoot, sourcePath)} to ${path.relative(repositoryRoot, destination.path)}`);
}
