import { access, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { assertTokensSupplied } from './template-tokens.mjs';
import { materializeTree } from './transform.mjs';

const PLATFORM_DIRS = {
  android: 'app/androidApp',
  ios: 'app/iosApp',
  harmony: 'app/harmonyApp',
};

const PLATFORM_SCRIPTS = {
  android: ['build:androidDebug', 'build:androidRelease', 'dev:android'],
  ios: ['build:iosDebug', 'build:iosRelease'],
  harmony: ['build:harmonyDebug', 'build:harmonyRelease'],
};

/**
 * Materialize the template snapshot into targetDir, then drop the native
 * platforms the user did not select.
 */
export async function copyTemplate(templateDir, targetDir, tokens) {
  if (await exists(targetDir)) {
    throw new Error(`target directory already exists: ${targetDir}`);
  }

  assertTokensSupplied(tokens);
  const selected = selectedPlatforms(tokens.platforms);
  await materializeTree(templateDir, targetDir, tokens);
  await configureSelectedPlatforms(targetDir, selected);

  for (const [platform, relativeDir] of Object.entries(PLATFORM_DIRS)) {
    if (selected.has(platform)) continue;
    await rm(join(targetDir, relativeDir), { recursive: true, force: true });
  }
}

function selectedPlatforms(platforms) {
  if (!Array.isArray(platforms) || platforms.length === 0) {
    throw new Error('at least one native platform must be selected');
  }
  const selected = new Set();
  for (const platform of platforms) {
    if (!Object.hasOwn(PLATFORM_DIRS, platform)) {
      throw new Error(`unknown native platform: ${String(platform)}`);
    }
    selected.add(platform);
  }
  return selected;
}

async function configureSelectedPlatforms(targetDir, selected) {
  const packageFile = join(targetDir, 'package.json');
  const packageJson = JSON.parse(await readFile(packageFile, 'utf8'));
  if (
    typeof packageJson.nativeApp !== 'object' ||
    packageJson.nativeApp === null ||
    Array.isArray(packageJson.nativeApp)
  ) {
    throw new Error('template package.json#nativeApp must be a JSON object');
  }
  if (
    typeof packageJson.scripts !== 'object' ||
    packageJson.scripts === null ||
    Array.isArray(packageJson.scripts)
  ) {
    throw new Error('template package.json#scripts must be a JSON object');
  }

  packageJson.nativeApp.platforms = Object.keys(PLATFORM_DIRS).filter(
    (platform) => selected.has(platform),
  );
  for (const platform of Object.keys(PLATFORM_DIRS)) {
    if (selected.has(platform)) continue;
    delete packageJson.nativeApp[platform];
    for (const script of PLATFORM_SCRIPTS[platform]) {
      delete packageJson.scripts[script];
    }
  }
  await writeFile(packageFile, `${JSON.stringify(packageJson, null, 2)}\n`);
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}
