#!/usr/bin/env node
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { copyTemplate } from '../src/copy.mjs';
import { resolveOptions } from '../src/prompt.mjs';

const packageRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const templateDir = resolve(packageRoot, 'template');

async function main() {
  const options = await resolveOptions(process.argv.slice(2));
  const targetDir = resolve(process.cwd(), options.name);

  await copyTemplate(templateDir, targetDir, options);

  console.info(`\nCreated ${options.name} in ${targetDir}`);
  console.info(`  scope:      @${options.scope}`);
  console.info(`  bundle ID:  ${options.package}`);
  console.info(`  HarmonyOS:  ${options.harmonyBundle}`);
  console.info(`  platforms:  ${options.platforms.join(', ')}`);

  console.info('\nNext steps:');
  console.info(`  cd ${options.name}`);
  console.info('  pnpm install');
  console.info('  pnpm build:lynx       # build bundles and sync embedded assets');
  console.info('  # then build each selected native host (see README.md)');
}

main().catch((error) => {
  console.error(`\nerror: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
