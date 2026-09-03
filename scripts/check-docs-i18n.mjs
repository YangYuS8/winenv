import { access, readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDirectory, "..");
const docs = path.join(root, "docs");

async function markdownFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await markdownFiles(target));
    if (entry.isFile() && entry.name.endsWith(".md")) files.push(target);
  }
  return files;
}

const allPages = await markdownFiles(docs);
const chineseRoot = path.join(docs, "zh") + path.sep;
const englishPages = allPages.filter((file) => !file.startsWith(chineseRoot));
const chinesePages = allPages.filter((file) => file.startsWith(chineseRoot));
const missing = [];

for (const english of englishPages) {
  const relative = path.relative(docs, english);
  const chinese = path.join(docs, "zh", relative);
  try {
    await access(chinese);
  } catch {
    missing.push(`Missing Simplified Chinese page for docs/${relative}`);
  }
}

for (const chinese of chinesePages) {
  const relative = path.relative(chineseRoot, chinese);
  const english = path.join(docs, relative);
  try {
    await access(english);
  } catch {
    missing.push(`Orphaned Simplified Chinese page: docs/zh/${relative}`);
  }
}

const policyPairs = [
  ["README.md", "README.zh-CN.md"],
  ["CONTRIBUTING.md", "CONTRIBUTING.zh-CN.md"],
  ["CODE_OF_CONDUCT.md", "CODE_OF_CONDUCT.zh-CN.md"],
  ["SECURITY.md", "SECURITY.zh-CN.md"],
  ["SUPPORT.md", "SUPPORT.zh-CN.md"],
  ["GOVERNANCE.md", "GOVERNANCE.zh-CN.md"],
];

for (const [english, chinese] of policyPairs) {
  for (const file of [english, chinese]) {
    try {
      const content = await readFile(path.join(root, file), "utf8");
      if (!content.trim()) missing.push(`Empty repository policy file: ${file}`);
    } catch {
      missing.push(`Missing repository policy file: ${file}`);
    }
  }
}

if (missing.length) {
  throw new Error(`Internationalized documentation is incomplete:\n- ${missing.join("\n- ")}`);
}

console.log(`Validated ${englishPages.length} English pages, ${chinesePages.length} Chinese pages, and ${policyPairs.length} bilingual policy pairs.`);
