import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { parsePage, translationChanges, policyPairs } from '../lib/docs.mjs';
import { auditSite, pageFacts, siteTarget } from '../check-docs-site.mjs';
import { preferredEntry, localeForPath } from '../../docs/public/locale.js';
import { needsRuntime } from '../classify-changes.mjs';

test('metadata and JSON examples fail closed', () => {
  assert.throws(() => parsePage('# Missing header', 'test'));
  assert.throws(() => parsePage('---\ntitle: test\n---\nBody', 'test'));
  assert.throws(() => parsePage('---\ntitle: test\ndescription: Test description\n---\n```json\n{bad}\n```', 'test'));
  assert.equal(parsePage('---\ntitle: test\ndescription: Test description\n---\nA complete document with useful prose.', 'test').metadata.title, 'test');
});

test('an English edit requires its translation in the same change', () => {
  const pairs = [['guide.md', 'zh/guide.md']];
  assert.equal(translationChanges(['guide.md'], pairs).length, 1);
  assert.equal(translationChanges(['guide.md', 'zh/guide.md'], pairs).length, 0);
  assert.equal(translationChanges(['zh/guide.md'], pairs).length, 0);
});

test('agent instructions participate in bilingual policy checks', () => {
  assert.ok(policyPairs.some(([english, chinese]) => english === 'AGENTS.md' && chinese === 'AGENTS.zh-CN.md'));
  assert.equal(translationChanges(['AGENTS.md'], policyPairs).length, 1);
  assert.equal(translationChanges(['AGENTS.md', 'AGENTS.zh-CN.md'], policyPairs).length, 0);
  assert.equal(translationChanges(['AGENTS.zh-CN.md'], policyPairs).length, 0);
});

test('HTML checks use parsed attributes, including Unicode fragments', () => {
  const facts = pageFacts('<h1 id="标题">Title</h1><a href="/winenv/zh/#%E6%A0%87%E9%A2%98">Link</a><code>&lt;a href="fake"&gt;</code>');
  assert.deepEqual([...facts.ids], ['标题']);
  assert.equal(facts.links.length, 1);
  assert.equal(siteTarget(facts.links[0], '/winenv/').fragment, '标题');
  assert.equal(siteTarget('https://github.com/test', '/winenv/'), null);
  assert.throws(() => siteTarget('/guide/', '/winenv/'));
});

test('entry detection respects manual choice and explicit URLs', () => {
  assert.equal(preferredEntry('/winenv/', null, ['zh-CN']), '/winenv/zh/');
  assert.equal(preferredEntry('/winenv/', 'en', ['zh-CN']), null);
  assert.equal(preferredEntry('/winenv/', 'zh', ['en-US']), '/winenv/zh/');
  assert.equal(preferredEntry('/winenv/', 'invalid', ['en-US']), null);
  assert.equal(preferredEntry('/winenv/guide/profiles/', 'zh', ['zh-CN']), null);
  assert.equal(preferredEntry('/winenv/zh/', 'en', ['en-US']), null);
  assert.equal(localeForPath('/winenv/zh/guide/profiles/'), 'zh');
  assert.equal(localeForPath('/winenv/guide/profiles/'), 'en');
});

test('site audit checks rendered routes, assets, anchors, and legacy compatibility', async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), 'winenv-docs-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(path.join(directory, 'guide'));
  await writeFile(path.join(directory, 'logo.png'), 'fixture');
  await writeFile(path.join(directory, 'index.html'), '<h1>Home</h1><a href="/winenv/guide/#section">Guide</a><img src="/winenv/logo.png">');
  await writeFile(path.join(directory, 'guide/index.html'), '<h1>Guide</h1><h2 id="section">Section</h2><a href="../">Home</a>');
  const legacy = { '/winenv/guide': ['section'] };
  assert.deepEqual((await auditSite(directory, legacy)).errors, []);
  await writeFile(path.join(directory, 'guide/index.html'), '<h1>Guide</h1><h2 id="duplicate">One</h2><h2 id="duplicate">Two</h2><a href="/winenv/missing/">Missing</a><img src="/winenv/missing.png">');
  const { errors } = await auditSite(directory, legacy);
  for (const problem of ['missing anchor', 'missing target /winenv/missing/', 'missing target /winenv/missing.png', 'duplicate id', 'Legacy anchor disappeared']) {
    assert.ok(errors.some((error) => error.includes(problem)), problem);
  }
});

test('only known documentation changes skip native runtime checks', () => {
  assert.equal(needsRuntime(['docs/src/content/docs/index.mdx', 'README.md']), false);
  assert.equal(needsRuntime(['docs/public/locale.js', 'scripts/check-docs-site.mjs']), false);
  assert.equal(needsRuntime(['src/Commands.ps1']), true);
  assert.equal(needsRuntime(['scripts/prepare-release.ps1']), true);
  assert.equal(needsRuntime(['.github/workflows/release.yml']), true);
  assert.equal(needsRuntime(['unexpected-new-file']), true);
});
