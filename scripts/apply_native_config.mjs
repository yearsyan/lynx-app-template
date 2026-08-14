import { randomUUID } from 'node:crypto';
import {
  chmod,
  readdir,
  readFile,
  rename,
  stat,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repositoryDirectory = resolve(dirname(scriptPath), '..');
const packageFile = join(repositoryDirectory, 'package.json');
const managedFiles = {
  android: join(repositoryDirectory, 'app/androidApp/app/build.gradle.kts'),
  ios: join(repositoryDirectory, 'app/iosApp/iosApp.xcodeproj/project.pbxproj'),
  harmony: join(repositoryDirectory, 'app/harmonyApp/AppScope/app.json5'),
};

// package.json#lynx.engineVersion is the single source for the engine version
// stamped into release manifests. Bundle builds and native hosts cannot read
// package.json, so they each hardcode the value; these patterns locate every
// copy so the audit below can keep them from drifting apart. The Kotlin file
// is found by name because its package directory differs per app
// (java/com/lynxapp here, java/<dotted bundle id segments> when scaffolded).
const engineVersionReferences = [
  {
    searchRoot: 'app/androidApp/app/src/main/java',
    searchFor: 'LynxBundleRepository.kt',
    pattern: /const val ENGINE_VERSION = "([^"]+)"/,
  },
  {
    path: 'app/iosApp/iosApp/LynxBundleRepository.swift',
    pattern: /static let engineVersion = "([^"]+)"/,
  },
  {
    path: 'app/harmonyApp/entry/src/main/ets/config/BundleConfig.ets',
    pattern: /static readonly ENGINE_VERSION: string = '([^']+)'/,
  },
];

const androidApplicationId =
  /^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/;
const appleBundleId = /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
const harmonyBundleName = androidApplicationId;

class NativeConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NativeConfigError';
  }
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function requireRecord(value, location) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new NativeConfigError(`${location} must be a JSON object`);
  }
  return value;
}

function optionalRecord(parent, key) {
  const value = Object.hasOwn(parent, key) ? parent[key] : {};
  return requireRecord(value, `package.json#nativeApp.${key}`);
}

function requiredString(parent, key, location) {
  const value = parent[key];
  if (typeof value !== 'string' || value.length === 0) {
    throw new NativeConfigError(
      `${location}.${key} must be a non-empty string`,
    );
  }
  return value;
}

function optionalString(parent, key, defaultValue, location) {
  const value = Object.hasOwn(parent, key) ? parent[key] : defaultValue;
  if (typeof value !== 'string') {
    throw new NativeConfigError(`${location}.${key} must be a string`);
  }
  return value;
}

function validateIdentifier(value, pattern, location) {
  if (!pattern.test(value)) {
    throw new NativeConfigError(
      `${location} has an invalid identifier: ${JSON.stringify(value)}`,
    );
  }
}

function effectiveAndroidDebugId(applicationId, suffix) {
  if (suffix.length === 0) return applicationId;
  return `${applicationId}${suffix.startsWith('.') ? suffix : `.${suffix}`}`;
}

async function loadNativeConfig() {
  let packageJson;
  try {
    packageJson = JSON.parse(await readFile(packageFile, 'utf8'));
  } catch (error) {
    throw new NativeConfigError(
      `cannot read ${packageFile}: ${errorMessage(error)}`,
    );
  }

  const packageData = requireRecord(packageJson, 'package.json');
  const nativeApp = requireRecord(
    packageData.nativeApp,
    'package.json#nativeApp',
  );
  const commonBundleId = requiredString(
    nativeApp,
    'bundleId',
    'package.json#nativeApp',
  );
  const android = optionalRecord(nativeApp, 'android');
  const ios = optionalRecord(nativeApp, 'ios');
  const harmony = optionalRecord(nativeApp, 'harmony');

  const config = {
    androidApplicationId: optionalString(
      android,
      'applicationId',
      commonBundleId,
      'package.json#nativeApp.android',
    ),
    androidDebugApplicationIdSuffix: optionalString(
      android,
      'debugApplicationIdSuffix',
      '',
      'package.json#nativeApp.android',
    ),
    iosBundleId: optionalString(
      ios,
      'bundleId',
      commonBundleId,
      'package.json#nativeApp.ios',
    ),
    harmonyBundleName: optionalString(
      harmony,
      'bundleName',
      commonBundleId,
      'package.json#nativeApp.harmony',
    ),
  };
  config.androidDebugApplicationId = effectiveAndroidDebugId(
    config.androidApplicationId,
    config.androidDebugApplicationIdSuffix,
  );

  validateIdentifier(
    config.androidApplicationId,
    androidApplicationId,
    'package.json#nativeApp.android.applicationId',
  );
  validateIdentifier(
    config.androidDebugApplicationId,
    androidApplicationId,
    'effective Android Debug applicationId',
  );
  validateIdentifier(
    config.iosBundleId,
    appleBundleId,
    'package.json#nativeApp.ios.bundleId',
  );
  validateIdentifier(
    config.harmonyBundleName,
    harmonyBundleName,
    'package.json#nativeApp.harmony.bundleName',
  );

  const lynx = requireRecord(packageData.lynx, 'package.json#lynx');
  config.engineVersion = requiredString(
    lynx,
    'engineVersion',
    'package.json#lynx',
  );
  return config;
}

async function findFileByName(rootDirectory, fileName) {
  let entries;
  try {
    entries = await readdir(rootDirectory, { withFileTypes: true });
  } catch (error) {
    throw new NativeConfigError(
      `cannot read ${rootDirectory}: ${errorMessage(error)}`,
    );
  }
  for (const entry of entries) {
    const path = join(rootDirectory, entry.name);
    if (entry.isDirectory()) {
      const found = await findFileByName(path, fileName);
      if (found !== null) return found;
    } else if (entry.isFile() && entry.name === fileName) {
      return path;
    }
  }
  return null;
}

async function collectEngineVersionMismatches(engineVersion) {
  const references = [];
  const bundleDirectory = join(repositoryDirectory, 'bundle');
  let bundleEntries;
  try {
    bundleEntries = await readdir(bundleDirectory, { withFileTypes: true });
  } catch (error) {
    throw new NativeConfigError(
      `cannot read ${bundleDirectory}: ${errorMessage(error)}`,
    );
  }
  for (const entry of bundleEntries) {
    if (!entry.isDirectory()) continue;
    references.push({
      path: join(bundleDirectory, entry.name, 'lynx.config.ts'),
      pattern: /engineVersion: '([^']+)'/,
      optional: true,
    });
  }
  for (const reference of engineVersionReferences) {
    if (reference.searchFor) {
      const root = join(repositoryDirectory, reference.searchRoot);
      const found = await findFileByName(root, reference.searchFor);
      if (found === null) {
        throw new NativeConfigError(
          `cannot find ${reference.searchFor} under ${reference.searchRoot}`,
        );
      }
      references.push({ path: found, pattern: reference.pattern });
      continue;
    }
    references.push({
      pattern: reference.pattern,
      path: join(repositoryDirectory, reference.path),
    });
  }

  const mismatches = [];
  for (const reference of references) {
    let content;
    try {
      content = await readFile(reference.path, 'utf8');
    } catch (error) {
      if (reference.optional && error?.code === 'ENOENT') continue;
      throw new NativeConfigError(
        `cannot read ${reference.path}: ${errorMessage(error)}`,
      );
    }
    const found = content.match(reference.pattern)?.[1];
    if (found !== engineVersion) {
      mismatches.push({ path: reference.path, found });
    }
  }
  return mismatches;
}

function replaceManagedValue(text, pattern, value, expectedCount, label) {
  let count = 0;
  const updated = text.replace(pattern, (_match, prefix, suffix) => {
    count += 1;
    return `${prefix}${value}${suffix}`;
  });
  if (count !== expectedCount) {
    throw new NativeConfigError(
      `expected ${expectedCount} managed ${label} value(s), found ${count}`,
    );
  }
  return updated;
}

async function buildUpdates(config) {
  let androidBefore;
  let iosBefore;
  let harmonyBefore;
  try {
    [androidBefore, iosBefore, harmonyBefore] = await Promise.all([
      readFile(managedFiles.android, 'utf8'),
      readFile(managedFiles.ios, 'utf8'),
      readFile(managedFiles.harmony, 'utf8'),
    ]);
  } catch (error) {
    throw new NativeConfigError(
      `cannot read managed native file: ${errorMessage(error)}`,
    );
  }

  let androidAfter = replaceManagedValue(
    androidBefore,
    /^(\s*applicationId\s*=\s*")[^"]*("\s*)$/gm,
    config.androidApplicationId,
    1,
    'Android applicationId',
  );
  androidAfter = replaceManagedValue(
    androidAfter,
    /^(\s*applicationIdSuffix\s*=\s*")[^"]*("\s*)$/gm,
    config.androidDebugApplicationIdSuffix,
    1,
    'Android Debug applicationIdSuffix',
  );
  const iosAfter = replaceManagedValue(
    iosBefore,
    /^(\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)[^;]+(;\s*)$/gm,
    config.iosBundleId,
    2,
    'iOS PRODUCT_BUNDLE_IDENTIFIER',
  );
  const harmonyAfter = replaceManagedValue(
    harmonyBefore,
    /^(\s*"bundleName"\s*:\s*")[^"]*("\s*,?\s*)$/gm,
    config.harmonyBundleName,
    1,
    'HarmonyOS bundleName',
  );

  return [
    {
      path: managedFiles.android,
      before: androidBefore,
      after: androidAfter,
    },
    { path: managedFiles.ios, before: iosBefore, after: iosAfter },
    {
      path: managedFiles.harmony,
      before: harmonyBefore,
      after: harmonyAfter,
    },
  ];
}

async function atomicWrite(update) {
  const mode = (await stat(update.path)).mode & 0o7777;
  const temporaryPath = join(
    dirname(update.path),
    `.${basename(update.path)}.${process.pid}.${randomUUID()}`,
  );
  try {
    await writeFile(temporaryPath, update.after, {
      encoding: 'utf8',
      flag: 'wx',
      mode,
    });
    await chmod(temporaryPath, mode);
    await rename(temporaryPath, update.path);
  } catch (error) {
    await unlink(temporaryPath).catch((unlinkError) => {
      if (unlinkError?.code !== 'ENOENT') throw unlinkError;
    });
    throw error;
  }
}

function repositoryRelative(path) {
  return relative(repositoryDirectory, path).split(sep).join('/');
}

function printIdentifiers(config) {
  console.info(`Android Release: ${config.androidApplicationId}`);
  console.info(`Android Debug:   ${config.androidDebugApplicationId}`);
  console.info(`iOS:             ${config.iosBundleId}`);
  console.info(`HarmonyOS:       ${config.harmonyBundleName}`);
}

function printHelp() {
  console.info(`usage: node scripts/apply_native_config.mjs [--check]

Apply package.json#nativeApp identifiers to the three native hosts and verify
that every Lynx engine version reference matches package.json#lynx.

options:
  --check  fail when native files do not match package.json without writing
  -h, --help  show this help message`);
}

async function main(args = process.argv.slice(2)) {
  if (args.includes('-h') || args.includes('--help')) {
    printHelp();
    return 0;
  }
  const unknownArguments = args.filter((argument) => argument !== '--check');
  if (unknownArguments.length > 0) {
    console.error(`error: unrecognized argument: ${unknownArguments[0]}`);
    return 2;
  }

  try {
    const config = await loadNativeConfig();
    const updates = await buildUpdates(config);
    const engineMismatches = await collectEngineVersionMismatches(
      config.engineVersion,
    );
    if (engineMismatches.length > 0) {
      console.error(
        `Lynx engine version references do not match package.json#lynx.engineVersion (${JSON.stringify(config.engineVersion)}):`,
      );
      for (const mismatch of engineMismatches) {
        console.error(
          `  - ${repositoryRelative(mismatch.path)} declares ${JSON.stringify(mismatch.found ?? 'no value')}`,
        );
      }
      console.error(
        'Update these files to the value from package.json (native:apply cannot rewrite them).',
      );
      return 1;
    }
    const changed = updates.filter((update) => update.before !== update.after);

    if (args.includes('--check')) {
      if (changed.length > 0) {
        console.error('Native configuration is out of date:');
        for (const update of changed) {
          console.error(`  - ${repositoryRelative(update.path)}`);
        }
        console.error('Run `pnpm native:apply` to update it.');
        return 1;
      }
      console.info('Native configuration is up to date.');
      printIdentifiers(config);
      return 0;
    }

    for (const update of changed) {
      await atomicWrite(update);
    }
    if (changed.length > 0) {
      console.info('Updated native configuration:');
      for (const update of changed) {
        console.info(`  - ${repositoryRelative(update.path)}`);
      }
    } else {
      console.info('Native configuration is already up to date.');
    }
    printIdentifiers(config);
    return 0;
  } catch (error) {
    console.error(`error: ${errorMessage(error)}`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  process.exitCode = await main();
}
