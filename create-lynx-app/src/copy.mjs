import { access, mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';

import { materializeTree } from './transform.mjs';

const PLATFORM_DIRS = {
  android: 'app/androidApp',
  ios: 'app/iosApp',
  harmony: 'app/harmonyApp',
};

/**
 * Materialize the template snapshot into targetDir, then drop the native
 * platforms the user did not select.
 */
export async function copyTemplate(templateDir, targetDir, tokens) {
  if (await exists(targetDir)) {
    throw new Error(`target directory already exists: ${targetDir}`);
  }

  await materializeTree(templateDir, targetDir, tokens);

  const selected = new Set(tokens.platforms);
  for (const [platform, relativeDir] of Object.entries(PLATFORM_DIRS)) {
    if (selected.has(platform)) continue;
    await rm(join(targetDir, relativeDir), { recursive: true, force: true });
  }
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}
