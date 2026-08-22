import { readFile } from 'node:fs/promises';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Repository root: scripts/lib/ -> scripts/ -> <root>. */
export const repositoryDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

export function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

export function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

export function requireRecord(value, location) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${location} must be a JSON object`);
  }
  return value;
}

export function repositoryRelative(path) {
  return relative(repositoryDirectory, path).split(sep).join('/');
}

export async function readRootPackageJson() {
  const packageFile = join(repositoryDirectory, 'package.json');
  try {
    return JSON.parse(await readFile(packageFile, 'utf8'));
  } catch (error) {
    throw new Error(`cannot read ${packageFile}: ${errorMessage(error)}`);
  }
}

/**
 * Read a pinned Lynx version from package.json#lynx. `engineVersion` and
 * `sdkVersion` feed release manifests and native host pins;
 * `harmonySdkVersion` is the ohpm @lynx/* pin shared by the HarmonyOS host
 * and every autolink HAR.
 */
export function requireLynxVersion(packageJson, key) {
  const lynx = requireRecord(packageJson.lynx, 'package.json#lynx');
  const value = lynx[key];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`package.json#lynx.${key} must be a non-empty string`);
  }
  return value;
}
