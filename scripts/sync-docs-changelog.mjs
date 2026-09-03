import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(repositoryRoot, "CHANGELOG.md");
const destinationPath = path.join(repositoryRoot, "docs", "changelog.md");

const source = await readFile(sourcePath, "utf8");
const body = source
  .trim()
  .split("\n")
  .map((line) => line.replace(/^(#{1,5})(\s+)/, "#$1$2"))
  .join("\n");

const page = `---
title: 更新日志
description: Winenv 的版本变化与发布记录
editLink: false
outline: [2, 4]
---

# 更新日志

此页面由根目录的 \`CHANGELOG.md\` 在构建时自动生成，与 GitHub Release 使用同一份提交记录。

${body}
`;

await writeFile(destinationPath, page, "utf8");
console.log(`Synced ${path.relative(repositoryRoot, sourcePath)} to ${path.relative(repositoryRoot, destinationPath)}`);
