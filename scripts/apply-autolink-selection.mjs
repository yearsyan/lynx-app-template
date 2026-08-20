import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import {
  autolinkDependencyIssues,
  autolinkNodeModulesIssues,
  configuredAutolinkModules,
  loadAutolinkModules,
  packageWithAutolinkSelection,
} from './lib/autolink-selection.mjs';
import {
  errorMessage,
  repositoryDirectory,
  requireRecord,
} from './lib/repo.mjs';

async function main() {
  const arguments_ = process.argv.slice(2);
  const unknownArguments = arguments_.filter(
    (argument) => argument !== '--check',
  );
  if (unknownArguments.length > 0) {
    throw new Error(`unknown argument(s): ${unknownArguments.join(', ')}`);
  }
  const checkOnly = arguments_.includes('--check');

  const packageFile = join(repositoryDirectory, 'package.json');
  const packageJson = requireRecord(
    JSON.parse(await readFile(packageFile, 'utf8')),
    'package.json',
  );
  const modules = await loadAutolinkModules();
  const selected = configuredAutolinkModules(packageJson, modules);
  const issues = autolinkDependencyIssues(packageJson, modules, selected);

  if (checkOnly) {
    issues.push(
      ...(await autolinkNodeModulesIssues(
        repositoryDirectory,
        modules,
        selected,
      )),
    );
    if (issues.length > 0) {
      throw new Error(
        `Autolink dependency selection is stale:\n- ${issues.join('\n- ')}\nRun pnpm native:autolink:apply, then pnpm install.`,
      );
    }
    console.info(
      `Autolink selection is up to date (${selected.length}/${modules.length} enabled).`,
    );
    return;
  }

  const updated = packageWithAutolinkSelection(packageJson, modules, selected);
  const output = `${JSON.stringify(updated, null, 2)}\n`;
  const current = await readFile(packageFile, 'utf8');
  if (output !== current) {
    await writeFile(packageFile, output, 'utf8');
    console.info(
      `Applied Autolink selection (${selected.length}/${modules.length} enabled).`,
    );
    console.info('Run pnpm install so node_modules and the lockfile match it.');
  } else {
    console.info(
      `Autolink dependencies already match the selection (${selected.length}/${modules.length} enabled).`,
    );
  }
}

main().catch((error) => {
  console.error(`error: ${errorMessage(error)}`);
  process.exit(1);
});
