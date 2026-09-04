import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { filesBelow, readPage, policyPairs, translationChanges } from './lib/docs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const content = path.join(root, 'docs/src/content/docs');
const pages = (await filesBelow(content)).filter((file) => /\.mdx?$/.test(file));
const relative = (file) => path.relative(root, file).split(path.sep).join('/');
const all = new Set(pages);
const pairs = [];
const errors = [];
for (const file of pages) {
  try { await readPage(file); } catch (error) { errors.push(error.message); }
  const key = path.relative(content, file);
  if (key.startsWith('zh' + path.sep)) {
    if (!all.has(path.join(content, key.slice(3)))) errors.push('Orphaned translation: ' + relative(file));
  } else {
    const chinese = path.join(content, 'zh', key);
    if (!all.has(chinese)) errors.push('Missing translation: ' + relative(chinese));
    if (!key.endsWith('changelog.md')) pairs.push([relative(file), relative(chinese)]);
  }
}
for (const pair of policyPairs) {
  for (const file of pair) {
    try { if (!(await readFile(path.join(root, file), 'utf8')).trim()) errors.push('Empty policy: ' + file); }
    catch { errors.push('Missing policy: ' + file); }
  }
}
const base = process.env.DOCS_DIFF_BASE;
if (base && !/^[a-f0-9]{40,64}$/.test(base)) throw new Error('DOCS_DIFF_BASE must be a full commit SHA.');
const args = base ? ['diff', '--name-only', '--no-renames', base, 'HEAD'] : ['diff', '--name-only', '--no-renames', 'HEAD'];
const changes = execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim().split('\n');
if (!base) changes.push(...execFileSync('git', ['ls-files', '--others', '--exclude-standard'], { cwd: root, encoding: 'utf8' }).trim().split('\n'));
errors.push(...translationChanges(changes, [...pairs, ...policyPairs]));
if (errors.length) throw new Error('Documentation checks failed:\n- ' + errors.join('\n- '));
console.log('Validated ' + pages.length + ' bilingual pages, metadata, JSON examples, ' + policyPairs.length + ' policy pairs, and paired translation changes.');
