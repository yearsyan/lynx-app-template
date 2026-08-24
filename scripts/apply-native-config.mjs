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
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  GRADLE_LYNX_COORDINATE,
  rewriteManagedValues,
} from './lib/autolink-boilerplate.mjs';
import { enabledNativePlatforms } from './lib/native-platforms.mjs';
import {
  errorMessage,
  repositoryDirectory,
  repositoryRelative,
  requireRecord,
} from './lib/repo.mjs';

const managedFiles = {
  android: join(repositoryDirectory, 'app/androidApp/app/build.gradle.kts'),
  ios: join(repositoryDirectory, 'app/iosApp/iosApp.xcodeproj/project.pbxproj'),
  harmony: join(repositoryDirectory, 'app/harmonyApp/AppScope/app.json5'),
};

// package.json#lynx.engineVersion is the single source for the engine version
// stamped into release manifests. Native hosts cannot read package.json, so
// this script writes the value into their config sources.
// The Kotlin file is found by name because its package directory differs per
// app (java/com.lynxapp here, java/<dotted bundle id segments> when
// scaffolded).
const engineVersionTargets = [
  {
    platform: 'android',
    searchRoot: 'app/androidApp/app/src/main/java',
    searchFor: 'LynxBundleRepository.kt',
    pattern: /(const val ENGINE_VERSION = ")[^"]*(")/,
    label: 'Android ENGINE_VERSION',
  },
  {
    platform: 'ios',
    path: 'app/iosApp/iosApp/LynxBundleRepository.swift',
    pattern: /(static let engineVersion = ")[^"]*(")/,
    label: 'iOS engineVersion',
  },
  {
    platform: 'harmony',
    path: 'app/harmonyApp/entry/src/main/ets/config/BundleConfig.ets',
    pattern: /(static readonly ENGINE_VERSION: string = ')[^']*(')/,
    label: 'HarmonyOS ENGINE_VERSION',
  },
];

// The ohpm @lynx/* packages ship together from one nightly channel, so the
// HarmonyOS host pins them all to package.json#lynx.harmonySdkVersion.
// @lynx/primjs follows a separate release channel and is intentionally left
// untouched. The same version is written into every autolink HAR by
// scripts/sync-native-modules.mjs.
const harmonyLynxPinTargets = [
  {
    path: 'app/harmonyApp/oh-package.json5',
    packages: [
      '@lynx/gfx',
      '@lynx/lynx',
      '@lynx/lynx_base',
      '@lynx/lynx_devtool',
      '@lynx/lynx_devtool_service',
      '@lynx/lynx_log_service',
    ],
  },
  {
    path: 'app/harmonyApp/entry/oh-package.json5',
    packages: ['@lynx/lynx', '@lynx/lynx_base', '@lynx/lynx_log_service'],
  },
];

// The host apps pin the same Lynx SDK version as the autolink packages
// (scripts/sync-native-modules.mjs manages those) via
// package.json#lynx.sdkVersion. The Gradle plugin and the servalsvg
// coordinate follow their own release channels and stay unmanaged; same for
// the third-party pods (DebugRouter, SDWebImage).
const hostGradleLynxFile = 'app/androidApp/app/build.gradle.kts';
const iosPodfilePath = 'app/iosApp/Podfile';
const managedPods = [
  'Lynx',
  'PrimJS',
  'LynxService',
  'LynxDevtool',
  'BaseDevtool',
  'XElement',
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

async function readJsonFile(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    throw new NativeConfigError(`cannot read ${path}: ${errorMessage(error)}`);
  }
}

async function loadNativeConfig() {
  const packageData = requireRecord(
    await readJsonFile(join(repositoryDirectory, 'package.json')),
    'package.json',
  );
  const nativeApp = requireRecord(
    packageData.nativeApp,
    'package.json#nativeApp',
  );
  const platforms = enabledNativePlatforms(packageData);
  const commonBundleId = requiredString(
    nativeApp,
    'bundleId',
    'package.json#nativeApp',
  );
  const config = {
    platforms,
  };

  if (platforms.includes('android')) {
    const android = optionalRecord(nativeApp, 'android');
    config.androidApplicationId = optionalString(
      android,
      'applicationId',
      commonBundleId,
      'package.json#nativeApp.android',
    );
    config.androidDebugApplicationIdSuffix = optionalString(
      android,
      'debugApplicationIdSuffix',
      '',
      'package.json#nativeApp.android',
    );
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
  }

  if (platforms.includes('ios')) {
    const ios = optionalRecord(nativeApp, 'ios');
    config.iosBundleId = optionalString(
      ios,
      'bundleId',
      commonBundleId,
      'package.json#nativeApp.ios',
    );
    validateIdentifier(
      config.iosBundleId,
      appleBundleId,
      'package.json#nativeApp.ios.bundleId',
    );
  }

  if (platforms.includes('harmony')) {
    const harmony = optionalRecord(nativeApp, 'harmony');
    config.harmonyBundleName = optionalString(
      harmony,
      'bundleName',
      commonBundleId,
      'package.json#nativeApp.harmony',
    );
    validateIdentifier(
      config.harmonyBundleName,
      harmonyBundleName,
      'package.json#nativeApp.harmony.bundleName',
    );
  }

  const lynx = requireRecord(packageData.lynx, 'package.json#lynx');
  config.engineVersion = requiredString(
    lynx,
    'engineVersion',
    'package.json#lynx',
  );
  if (platforms.includes('android') || platforms.includes('ios')) {
    config.sdkVersion = requiredString(lynx, 'sdkVersion', 'package.json#lynx');
  }
  if (platforms.includes('harmony')) {
    config.harmonySdkVersion = requiredString(
      lynx,
      'harmonySdkVersion',
      'package.json#lynx',
    );
  }
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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function readManagedFile(path) {
  try {
    return await readFile(path, 'utf8');
  } catch (error) {
    throw new NativeConfigError(
      `cannot read ${repositoryRelative(path)}: ${errorMessage(error)}`,
    );
  }
}

async function collectIdentifierUpdates(config) {
  const updates = [];
  for (const platform of config.platforms) {
    const path = managedFiles[platform];
    const before = await readManagedFile(path);

    let after = before;
    if (platform === 'android') {
      after = replaceManagedValue(
        after,
        /^(\s*applicationId\s*=\s*")[^"]*("\s*)$/gm,
        config.androidApplicationId,
        1,
        'Android applicationId',
      );
      after = replaceManagedValue(
        after,
        /^(\s*applicationIdSuffix\s*=\s*")[^"]*("\s*)$/gm,
        config.androidDebugApplicationIdSuffix,
        1,
        'Android Debug applicationIdSuffix',
      );
      // The application identifiers and Lynx pins share one Gradle file, so
      // apply both transformations to the same in-memory update. Emitting two
      // independent updates for this path would let the second atomic write
      // restore the first value when both settings change together.
      const { updated, count } = rewriteManagedValues(
        after,
        GRADLE_LYNX_COORDINATE,
        config.sdkVersion,
      );
      if (count === 0) {
        throw new NativeConfigError(
          `expected org.lynxsdk.lynx:* pins in ${hostGradleLynxFile}, found none`,
        );
      }
      after = updated;
    } else if (platform === 'ios') {
      after = replaceManagedValue(
        after,
        /^(\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)[^;]+(;\s*)$/gm,
        config.iosBundleId,
        2,
        'iOS PRODUCT_BUNDLE_IDENTIFIER',
      );
    } else {
      after = replaceManagedValue(
        after,
        /^(\s*"bundleName"\s*:\s*")[^"]*("\s*,?\s*)$/gm,
        config.harmonyBundleName,
        1,
        'HarmonyOS bundleName',
      );
    }
    updates.push({ path, before, after });
  }
  return updates;
}

async function collectEngineVersionUpdates(config) {
  const updates = [];
  const enabled = new Set(config.platforms);
  for (const target of engineVersionTargets) {
    if (!enabled.has(target.platform)) continue;
    let path;
    if (target.searchFor) {
      const root = join(repositoryDirectory, target.searchRoot);
      const found = await findFileByName(root, target.searchFor);
      if (found === null) {
        throw new NativeConfigError(
          `cannot find ${target.searchFor} under ${target.searchRoot}`,
        );
      }
      path = found;
    } else {
      path = join(repositoryDirectory, target.path);
    }
    const before = await readManagedFile(path);
    const after = replaceManagedValue(
      before,
      target.pattern,
      config.engineVersion,
      1,
      target.label,
    );
    updates.push({ path, before, after });
  }
  return updates;
}

async function collectHarmonyLynxPinUpdates(config) {
  if (!config.platforms.includes('harmony')) return [];
  const updates = [];
  for (const target of harmonyLynxPinTargets) {
    const path = join(repositoryDirectory, target.path);
    const before = await readManagedFile(path);
    let after = before;
    for (const name of target.packages) {
      after = replaceManagedValue(
        after,
        new RegExp(`("${escapeRegExp(name)}"\\s*:\\s*")[^"]*(")`, 'g'),
        config.harmonySdkVersion,
        1,
        `${target.path} ${name}`,
      );
    }
    updates.push({ path, before, after });
  }
  return updates;
}

async function collectHostLynxPinUpdates(config) {
  const enabled = new Set(config.platforms);
  const updates = [];
  if (enabled.has('ios')) {
    const path = join(repositoryDirectory, iosPodfilePath);
    const before = await readManagedFile(path);
    let after = before;
    for (const pod of managedPods) {
      after = replaceManagedValue(
        after,
        new RegExp(`(pod '${pod}', ')[^']*(')`, 'g'),
        config.sdkVersion,
        1,
        `Podfile ${pod}`,
      );
    }
    updates.push({ path, before, after });
  }
  return updates;
}

async function buildUpdates(config) {
  return [
    ...(await collectIdentifierUpdates(config)),
    ...(await collectEngineVersionUpdates(config)),
    ...(await collectHarmonyLynxPinUpdates(config)),
    ...(await collectHostLynxPinUpdates(config)),
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

function printIdentifiers(config) {
  if (config.platforms.includes('android')) {
    console.info(`Android Release: ${config.androidApplicationId}`);
    console.info(`Android Debug:   ${config.androidDebugApplicationId}`);
  }
  if (config.platforms.includes('ios')) {
    console.info(`iOS:             ${config.iosBundleId}`);
  }
  if (config.platforms.includes('harmony')) {
    console.info(`HarmonyOS:       ${config.harmonyBundleName}`);
  }
}

function printHelp() {
  console.info(`usage: node scripts/apply-native-config.mjs [--check]

Apply package.json to the enabled native hosts: nativeApp identifiers, the
Lynx engine version (package.json#lynx.engineVersion), the host Lynx SDK pins
(package.json#lynx.sdkVersion) and the HarmonyOS @lynx/* ohpm pins
(package.json#lynx.harmonySdkVersion).

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

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  process.exitCode = await main();
}
