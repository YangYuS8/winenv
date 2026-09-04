import { readFileSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

export function needsRuntime(files) {
  return files.some((file) => !(
    file.startsWith('docs/') ||
    /^[^/]+\.md$/.test(file) ||
    file.startsWith('.github/ISSUE_TEMPLATE/') ||
    file === '.github/PULL_REQUEST_TEMPLATE.md' ||
    file === 'playwright.config.mjs' ||
    file.startsWith('scripts/tests/') ||
    /^scripts\/(?:check-docs[^/]*|sync-docs-changelog|docs-legacy-routes)\.(?:mjs|json)$/.test(file) ||
    file === 'scripts/lib/docs.mjs'
  ));
}

if (import.meta.main) {
  const event = process.env.GITHUB_EVENT_PATH ? JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : {};
  let base = event.pull_request?.base?.sha || event.before || '';
  let runtime = true;
  if (/^[a-f0-9]{40,64}$/.test(base) && !/^0+$/.test(base)) {
    try {
      const files = execFileSync('git', ['diff', '--name-only', '--no-renames', base, 'HEAD'], { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
      runtime = needsRuntime(files);
    } catch {
      // Missing history or a force push must never suppress runtime checks.
      base = '';
    }
  } else base = '';
  const result = `runtime=${runtime}\nbase=${base}\n`;
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, result);
  console.log(result.trim());
}
