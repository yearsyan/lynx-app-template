import { access, readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import {
  enabledNativePlatforms,
  SUPPORTED_NATIVE_PLATFORMS,
} from './native-platforms.mjs';
import { repositoryDirectory, requireRecord } from './repo.mjs';

const MODULE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const DEPENDENCY_SECTIONS = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
];

function compareNames(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function titleFromName(name) {
  return name
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

async function readJson(path, location) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    throw new Error(
      `cannot read ${location} (${path}): ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function requireStringArray(value, location) {
  if (!Array.isArray(value)) {
    throw new Error(`${location} must be an array`);
  }
  const seen = new Set();
  for (const [index, item] of value.entries()) {
    if (typeof item !== 'string' || item.length === 0) {
      throw new Error(`${location}[${index}] must be a non-empty string`);
    }
    if (seen.has(item)) {
      throw new Error(
        `${location}[${index}] duplicates ${JSON.stringify(item)}`,
      );
    }
    seen.add(item);
  }
  return [...value];
}

function selectedPlatformSet(platforms) {
  const wrapper = { nativeApp: { platforms } };
  return new Set(enabledNativePlatforms(wrapper));
}

export function applicableAutolinkModules(modules, platforms) {
  const selectedPlatforms = selectedPlatformSet(platforms);
  return modules.filter((module) =>
    module.platforms.some((platform) => selectedPlatforms.has(platform)),
  );
}

export function requiredAutolinkModuleNames(modules, platforms) {
  const selectedPlatforms = selectedPlatformSet(platforms);
  return new Set(
    modules
      .filter((module) =>
        module.requiredFor.some((platform) => selectedPlatforms.has(platform)),
      )
      .map((module) => module.name),
  );
}

/**
 * Resolve CLI/scaffolder input. Required host integrations are added even
 * when the caller asks for `none` or only names optional modules.
 */
export function resolveAutolinkSelection(modules, platforms, requested) {
  const applicable = applicableAutolinkModules(modules, platforms);
  const applicableByName = new Map(
    applicable.map((module) => [module.name, module]),
  );
  const allByName = new Map(modules.map((module) => [module.name, module]));
  const required = requiredAutolinkModuleNames(modules, platforms);

  if (requested === undefined || requested === 'all') {
    return applicable.map((module) => module.name);
  }

  let values = requested === 'none' ? [] : requested;
  if (!Array.isArray(values)) {
    throw new Error('Autolink selection must be `all`, `none`, or an array');
  }
  values = requireStringArray(values, 'Autolink selection');

  if (values.includes('all') || values.includes('none')) {
    if (values.length !== 1) {
      throw new Error('`all` or `none` cannot be combined with module names');
    }
    return resolveAutolinkSelection(modules, platforms, values[0]);
  }

  const selected = new Set(required);
  for (const name of values) {
    if (!allByName.has(name)) {
      throw new Error(`unknown Autolink module: ${name}`);
    }
    if (!applicableByName.has(name)) {
      throw new Error(
        `Autolink module ${name} does not support the selected native platforms`,
      );
    }
    selected.add(name);
  }
  return applicable
    .filter((module) => selected.has(module.name))
    .map((module) => module.name);
}

/** Validate the committed package.json selection without silently fixing it. */
export function configuredAutolinkModules(packageJson, modules) {
  const packageData = requireRecord(packageJson, 'package.json');
  const nativeApp = requireRecord(
    packageData.nativeApp,
    'package.json#nativeApp',
  );
  const platforms = enabledNativePlatforms(packageData);
  const configured = requireStringArray(
    nativeApp.autolinkModules,
    'package.json#nativeApp.autolinkModules',
  );
  const applicable = new Set(
    applicableAutolinkModules(modules, platforms).map((module) => module.name),
  );
  const known = new Set(modules.map((module) => module.name));

  for (const name of configured) {
    if (!known.has(name)) {
      throw new Error(
        `package.json#nativeApp.autolinkModules contains unknown module ${JSON.stringify(name)}`,
      );
    }
    if (!applicable.has(name)) {
      throw new Error(
        `package.json#nativeApp.autolinkModules includes ${JSON.stringify(name)}, which does not support an enabled platform`,
      );
    }
  }

  const configuredSet = new Set(configured);
  const missing = [...requiredAutolinkModuleNames(modules, platforms)].filter(
    (name) => !configuredSet.has(name),
  );
  if (missing.length > 0) {
    throw new Error(
      `package.json#nativeApp.autolinkModules is missing host-required module(s): ${missing.join(', ')}`,
    );
  }
  return configured;
}

/**
 * Discover every Autolink library from its package and lynx.lib.json files.
 * The catalog only owns stable UX/policy metadata; platform support remains
 * single-sourced in the official Lynx manifest.
 */
export async function loadAutolinkModules(rootDirectory = repositoryDirectory) {
  const catalogFile = join(rootDirectory, 'config', 'autolink-modules.json');
  const catalog = requireRecord(
    await readJson(catalogFile, 'Autolink module catalog'),
    'config/autolink-modules.json',
  );
  if (catalog.schemaVersion !== 1) {
    throw new Error(
      'config/autolink-modules.json#schemaVersion must currently be 1',
    );
  }
  if (!Array.isArray(catalog.modules)) {
    throw new Error('config/autolink-modules.json#modules must be an array');
  }

  const supportedPlatforms = new Set(SUPPORTED_NATIVE_PLATFORMS);
  const seen = new Set();
  const modules = [];
  for (const [index, rawEntry] of catalog.modules.entries()) {
    const location = `config/autolink-modules.json#modules[${index}]`;
    const entry = requireRecord(rawEntry, location);
    const { name } = entry;
    if (typeof name !== 'string' || !MODULE_NAME.test(name)) {
      throw new Error(`${location}.name must be kebab-case`);
    }
    if (seen.has(name)) {
      throw new Error(`${location}.name duplicates ${JSON.stringify(name)}`);
    }
    seen.add(name);

    const requiredFor =
      entry.requiredFor === undefined
        ? []
        : requireStringArray(entry.requiredFor, `${location}.requiredFor`);
    const packageDirectory = join(rootDirectory, 'autolink', name);
    const packageJson = requireRecord(
      await readJson(join(packageDirectory, 'package.json'), `${name} package`),
      `autolink/${name}/package.json`,
    );
    const manifest = requireRecord(
      await readJson(
        join(packageDirectory, 'lynx.lib.json'),
        `${name} Lynx manifest`,
      ),
      `autolink/${name}/lynx.lib.json`,
    );
    const manifestPlatforms = requireRecord(
      manifest.platforms,
      `autolink/${name}/lynx.lib.json#platforms`,
    );
    const platforms = SUPPORTED_NATIVE_PLATFORMS.filter((platform) =>
      Object.hasOwn(manifestPlatforms, platform),
    );
    if (platforms.length === 0) {
      throw new Error(`autolink/${name}/lynx.lib.json supports no native host`);
    }
    for (const platform of requiredFor) {
      if (!supportedPlatforms.has(platform)) {
        throw new Error(`${location}.requiredFor has unknown host ${platform}`);
      }
      if (!platforms.includes(platform)) {
        throw new Error(
          `${location}.requiredFor includes unsupported host ${platform}`,
        );
      }
    }
    if (typeof packageJson.name !== 'string' || packageJson.name.length === 0) {
      throw new Error(`autolink/${name}/package.json#name must be a string`);
    }

    modules.push({
      name,
      label:
        typeof entry.label === 'string' && entry.label.length > 0
          ? entry.label
          : titleFromName(name),
      packageName: packageJson.name,
      platforms,
      requiredFor,
    });
  }

  const sortedNames = [...seen].sort(compareNames);
  if (JSON.stringify([...seen]) !== JSON.stringify(sortedNames)) {
    throw new Error('config/autolink-modules.json#modules must be name-sorted');
  }

  const libraryDirectories = [];
  for (const entry of await readdir(join(rootDirectory, 'autolink'), {
    withFileTypes: true,
  })) {
    if (!entry.isDirectory()) continue;
    try {
      await access(
        join(rootDirectory, 'autolink', entry.name, 'lynx.lib.json'),
      );
      libraryDirectories.push(entry.name);
    } catch {
      // A workspace directory without Lynx metadata is not an Autolink library.
    }
  }
  libraryDirectories.sort(compareNames);
  const missing = libraryDirectories.filter((name) => !seen.has(name));
  if (missing.length > 0) {
    throw new Error(
      `config/autolink-modules.json is missing library directory/directories: ${missing.join(', ')}`,
    );
  }
  return modules;
}

function sortedRecord(record) {
  return Object.fromEntries(
    Object.entries(record).sort(([left], [right]) => compareNames(left, right)),
  );
}

export function packageWithAutolinkSelection(
  packageJson,
  modules,
  selectedNames,
) {
  const next = structuredClone(requireRecord(packageJson, 'package.json'));
  const selected = new Set(selectedNames);
  const packageNames = new Set(modules.map((module) => module.packageName));

  for (const section of DEPENDENCY_SECTIONS) {
    if (next[section] === undefined) continue;
    const dependencies = requireRecord(
      next[section],
      `package.json#${section}`,
    );
    for (const packageName of packageNames) delete dependencies[packageName];
    next[section] = sortedRecord(dependencies);
  }

  const devDependencies = requireRecord(
    next.devDependencies ?? {},
    'package.json#devDependencies',
  );
  for (const module of modules) {
    if (selected.has(module.name)) {
      devDependencies[module.packageName] = 'workspace:*';
    }
  }
  next.devDependencies = sortedRecord(devDependencies);
  return next;
}

export function autolinkDependencyIssues(packageJson, modules, selectedNames) {
  const packageData = requireRecord(packageJson, 'package.json');
  const selected = new Set(selectedNames);
  const issues = [];
  for (const module of modules) {
    for (const section of DEPENDENCY_SECTIONS) {
      const dependencies = packageData[section];
      const value =
        dependencies && typeof dependencies === 'object'
          ? dependencies[module.packageName]
          : undefined;
      if (section === 'devDependencies' && selected.has(module.name)) {
        if (value !== 'workspace:*') {
          issues.push(
            `package.json#devDependencies[${JSON.stringify(module.packageName)}] must be ${JSON.stringify('workspace:*')}`,
          );
        }
      } else if (value !== undefined) {
        issues.push(
          `${module.packageName} must not appear in package.json#${section}`,
        );
      }
    }
  }
  return issues;
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * When pnpm metadata exists, verify the links the native scanners can really
 * see. This catches editing/applying package.json without rerunning install.
 */
export async function autolinkNodeModulesIssues(
  rootDirectory,
  modules,
  selectedNames,
) {
  const nodeModules = join(rootDirectory, 'node_modules');
  if (!(await exists(join(nodeModules, '.modules.yaml')))) return [];

  const selected = new Set(selectedNames);
  const results = await Promise.all(
    modules.map(async (module) => {
      const manifest = join(
        nodeModules,
        ...module.packageName.split('/'),
        'lynx.lib.json',
      );
      const linked = await exists(manifest);
      if (selected.has(module.name) && !linked) {
        return `${module.packageName} is selected but not linked directly in node_modules`;
      }
      if (!selected.has(module.name) && linked) {
        return `${module.packageName} is disabled but still linked directly in node_modules`;
      }
      return undefined;
    }),
  );
  return results.filter(Boolean);
}
