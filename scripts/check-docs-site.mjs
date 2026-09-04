import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'parse5';
import { filesBelow } from './lib/docs.mjs';

export function pageFacts(html) {
  const ids = new Set();
  const duplicates = [];
  const links = [];
  const headings = [];
  const unparsedBold = [];
  const visit = (node, inProse = false) => {
    const attrs = Object.fromEntries((node.attrs || []).map(({ name, value }) => [name, value]));
    if ((attrs.class || '').split(/\s+/).includes('sl-markdown-content')) inProse = true;
    if (['code', 'pre', 'script', 'style'].includes(node.tagName)) inProse = false;
    if (inProse && node.nodeName === '#text') {
      for (const match of node.value.matchAll(/\*\*(?=\S)([^*\n]*\S)\*\*/g)) unparsedBold.push(match[0]);
    }
    if (attrs.id) {
      if (ids.has(attrs.id)) duplicates.push(attrs.id);
      ids.add(attrs.id);
    }
    if (/^h[1-6]$/.test(node.tagName)) headings.push(node.tagName);
    for (const key of ['href', 'src']) if (attrs[key]) links.push(attrs[key]);
    for (const child of node.childNodes || []) visit(child, inProse);
  };
  visit(parse(html));
  return { ids, links, headings, duplicates, unparsedBold };
}

export function siteTarget(link, current, base = '/winenv/') {
  const url = new URL(link, `https://yangyus8.top${current}`);
  if (url.origin !== 'https://yangyus8.top') return null;
  if (!url.pathname.startsWith(base)) throw new Error(`link escapes site base: ${link}`);
  const relative = decodeURIComponent(url.pathname.slice(base.length));
  if (relative.split('/').includes('..')) throw new Error(`unsafe path: ${link}`);
  return { relative, fragment: decodeURIComponent(url.hash.slice(1)) };
}

export async function auditSite(directory, legacy = {}) {
  const errors = [];
  const pages = new Map();
  for (const file of await filesBelow(directory)) {
    if (file.endsWith('.html')) pages.set(path.relative(directory, file).split(path.sep).join('/'), pageFacts(await readFile(file, 'utf8')));
  }
  async function resolve(relative) {
    for (const candidate of [relative, `${relative}.html`, `${relative.replace(/\/$/, '')}/index.html`.replace(/^\//, '')]) {
      if (pages.has(candidate)) return { page: pages.get(candidate), file: candidate };
      if (!candidate || candidate.endsWith('/')) continue;
      try { if ((await stat(path.join(directory, candidate))).isFile()) return { file: candidate }; } catch { /* Try clean URL. */ }
    }
    return null;
  }
  for (const [file, facts] of pages) {
    const route = '/winenv/' + file.replace(/index\.html$/, '').replace(/\.html$/, '');
    if (facts.headings.filter((h) => h === 'h1').length !== 1) errors.push(`${route}: expected exactly one h1`);
    for (const id of facts.duplicates) errors.push(`${route}: duplicate id ${id}`);
    for (const marker of facts.unparsedBold) errors.push(`${route}: unparsed bold marker in prose: ${marker}`);
    for (const link of facts.links) {
      let target;
      try { target = siteTarget(link, route); } catch (error) { errors.push(`${route}: ${error.message}`); continue; }
      if (!target) continue;
      const resolved = await resolve(target.relative);
      if (!resolved) errors.push(`${route}: missing target ${link}`);
      else if (target.fragment && resolved.page && !resolved.page.ids.has(target.fragment)) errors.push(`${route}: missing anchor ${link}`);
    }
  }
  for (const [route, anchors] of Object.entries(legacy)) {
    const resolved = await resolve(route.slice('/winenv/'.length));
    if (!resolved?.page) { errors.push(`Legacy route disappeared: ${route}`); continue; }
    for (const anchor of anchors) if (!resolved.page.ids.has(anchor)) errors.push(`Legacy anchor disappeared: ${route}#${anchor}`);
  }
  return { errors: [...new Set(errors)], count: pages.size };
}

if (import.meta.main) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const legacy = JSON.parse(await readFile(path.join(root, 'scripts/docs-legacy-routes.json'), 'utf8'));
  const result = await auditSite(path.join(root, 'docs/dist'), legacy);
  if (result.errors.length) throw new Error(`Documentation checks failed:\n- ${result.errors.join('\n- ')}`);
  console.log(`Validated ${result.count} HTML pages, prose bold markers, local links/assets, fragments, and ${Object.keys(legacy).length} legacy routes.`);
}
