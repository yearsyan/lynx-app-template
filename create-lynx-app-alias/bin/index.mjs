#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// Delegate to the real scaffolder. The create-* package is only present so
// that `npm create @sairo/lynx-app` resolves to a package whose name carries
// the `create-` prefix npm expects.
const entry = require.resolve('@sairo/lynx-app/bin/index.mjs');
const result = spawnSync(process.execPath, [entry, ...process.argv.slice(2)], {
  stdio: 'inherit',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 0);
