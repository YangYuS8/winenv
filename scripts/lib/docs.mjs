import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import yaml from 'js-yaml';

export async function filesBelow(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesBelow(target));
    else files.push(target);
  }
  return files;
}

export function parsePage(source, name) {
  const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/);
  if (!match) throw new Error(`${name}: missing frontmatter`);
  const metadata = yaml.load(match[1], { schema: yaml.JSON_SCHEMA });
  for (const key of ['title', 'description']) {
    if (typeof metadata?.[key] !== 'string' || !metadata[key].trim()) {
      throw new Error(`${name}: missing ${key}`);
    }
  }
  const body = source.slice(match[0].length);
  if (body.replace(/<[^>]+>/g, '').trim().length < 20) throw new Error(`${name}: empty content`);
  for (const code of body.matchAll(/^```json\s*\r?\n([\s\S]*?)^```/gm)) {
    try { JSON.parse(code[1]); } catch { throw new Error(`${name}: invalid JSON example`); }
  }
  return { metadata, body };
}

export const policyPairs = ['README', 'CONTRIBUTING', 'CODE_OF_CONDUCT', 'SECURITY', 'SUPPORT', 'GOVERNANCE', 'AGENTS']
  .map((name) => [`${name}.md`, `${name}.zh-CN.md`]);

export function translationChanges(changed, pairs) {
  const set = new Set(changed);
  return pairs.filter(([english, chinese]) => set.has(english) && !set.has(chinese))
    .map(([english, chinese]) => `${english} changed without ${chinese}; update or explicitly review its translation in the same change.`);
}

export async function readPage(file) {
  return parsePage(await readFile(file, 'utf8'), file);
}
