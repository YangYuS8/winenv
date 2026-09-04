import { writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const sourceSha = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (!/^[a-f0-9]{40}$/.test(sourceSha)) throw new Error('Invalid documentation source revision.');
const record = { sourceSha, triggerSha: process.env.GITHUB_SHA, runId: process.env.GITHUB_RUN_ID };
writeFileSync(path.join(process.env.RUNNER_TEMP, 'docs-source.json'), JSON.stringify(record) + '\n');
console.log(`Documentation source: ${sourceSha}`);
