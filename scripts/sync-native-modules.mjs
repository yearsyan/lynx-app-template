// Re-sync the boilerplate every autolink package shares, so the scaffold
// output in scripts/create-native-module.mjs stays the single source even
// after it evolves:
//
//   harmony/hvigorfile.ts, harmony/build-profile.json5   byte-identical files
//   harmony/src/main/module.json5                        name derived from the
//                                                        package directory
//   harmony/oh-package.json5                             @lynx/lynx pinned to
//                                                        package.json#lynx.harmonySdkVersion
//   android/build.gradle.kts                             org.lynxsdk.lynx:*
//                                                        pinned to package.json#lynx.sdkVersion
//
// Module-specific sources (Java/ObjC/ETS implementations, extra gradle or
// ohpm dependencies, podspecs) are never touched. Packages without an
// android/ or harmony/ directory (e.g. the iOS-only liquid-glass element)
// are skipped per platform.
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  GRADLE_LYNX_COORDINATE,
  HARMONY_LYNX_DEPENDENCY,
  harmonyBuildProfile,
  harmonyHvigorfile,
  harmonyModuleJson,
  rewriteManagedValues,
} from './lib/autolink-boilerplate.mjs';
import {
  errorMessage,
  readRootPackageJson,
  repositoryDirectory,
  repositoryRelative,
  requireLynxVersion,
} from './lib/repo.mjs';

const autolinkDirectory = join(repositoryDirectory, 'autolink');

class SyncError extends Error {
  constructor(message) {
    super(message);
    this.name = 'SyncError';
  }
}

async function readIfExists(path) {
  try {
    return await readFile(path, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

function rewrite(target, pattern, value, minimumCount, label) {
  const { updated, count } = rewriteManagedValues(target, pattern, value);
  if (count < minimumCount) {
    throw new SyncError(
      `expected at least ${minimumCount} ${label} value(s), found ${count}`,
    );
  }
  return updated;
}

async function collectPackageUpdates(entryName, versions) {
  const packageDirectory = join(autolinkDirectory, entryName);
  const updates = [];

  const harmonyDirectory = join(packageDirectory, 'harmony');
  const harmonyMarker = await readIfExists(
    join(harmonyDirectory, 'oh-package.json5'),
  );
  if (harmonyMarker !== null) {
    updates.push(
      {
        path: join(harmonyDirectory, 'hvigorfile.ts'),
        after: harmonyHvigorfile(),
      },
      {
        path: join(harmonyDirectory, 'build-profile.json5'),
        after: harmonyBuildProfile(),
      },
      {
        path: join(harmonyDirectory, 'src/main/module.json5'),
        after: harmonyModuleJson(entryName),
      },
      {
        path: join(harmonyDirectory, 'oh-package.json5'),
        after: rewrite(
          harmonyMarker,
          HARMONY_LYNX_DEPENDENCY,
          versions.harmonySdkVersion,
          1,
          `${entryName} @lynx/lynx`,
        ),
      },
    );
  }

  const gradlePath = join(packageDirectory, 'android/build.gradle.kts');
  const gradle = await readIfExists(gradlePath);
  if (gradle !== null) {
    updates.push({
      path: gradlePath,
      after: rewrite(
        gradle,
        GRADLE_LYNX_COORDINATE,
        versions.sdkVersion,
        1,
        `${entryName} org.lynxsdk.lynx:*`,
      ),
    });
  }

  return updates;
}

async function collectUpdates(versions) {
  const entries = await readdir(autolinkDirectory, { withFileTypes: true });
  const updates = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    for (const update of await collectPackageUpdates(entry.name, versions)) {
      const before = await readIfExists(update.path);
      updates.push({ ...update, before });
    }
  }
  return updates;
}

function printHelp() {
  console.info(`usage: node scripts/sync-native-modules.mjs [--check]

Re-sync shared autolink package boilerplate (HarmonyOS hvigor/build files,
module.json5, @lynx/lynx ohpm pin, org.lynxsdk.lynx:* gradle pins) with the
canonical templates and package.json#lynx versions.

options:
  --check  fail when any autolink package has drifted without writing
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
    const packageJson = await readRootPackageJson();
    const versions = {
      sdkVersion: requireLynxVersion(packageJson, 'sdkVersion'),
      harmonySdkVersion: requireLynxVersion(packageJson, 'harmonySdkVersion'),
    };
    const updates = await collectUpdates(versions);
    const changed = updates.filter((update) => update.before !== update.after);

    if (args.includes('--check')) {
      if (changed.length > 0) {
        console.error('Autolink module boilerplate is out of date:');
        for (const update of changed) {
          console.error(`  - ${repositoryRelative(update.path)}`);
        }
        console.error('Run `pnpm native:modules:sync` to update it.');
        return 1;
      }
      console.info(
        `Autolink module boilerplate is up to date (${updates.length} managed files).`,
      );
      return 0;
    }

    for (const update of changed) {
      await writeFile(update.path, update.after, 'utf8');
    }
    if (changed.length > 0) {
      console.info('Updated autolink module boilerplate:');
      for (const update of changed) {
        console.info(`  - ${repositoryRelative(update.path)}`);
      }
    } else {
      console.info(
        `Autolink module boilerplate is already up to date (${updates.length} managed files).`,
      );
    }
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
