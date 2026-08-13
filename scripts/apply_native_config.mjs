import { randomUUID } from 'node:crypto';
import {
  chmod,
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
  return config;
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

Apply package.json#nativeApp identifiers to the three native hosts.

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

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  process.exitCode = await main();
}
