import { copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

// GitHub Pages serves /404.html for unknown URLs. The regular /404/ document
// remains available so the language picker and canonical links also work.
const directory = fileURLToPath(new URL('../docs/dist/', import.meta.url));
await copyFile(`${directory}404/index.html`, `${directory}404.html`);
