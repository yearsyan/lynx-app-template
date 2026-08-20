// Build the Android Debug APK, install it, and launch it on a device.
//
// Usage:
//   pnpm dev:android               # single attached device, or pick with -s
//   pnpm dev:android -s <serial>   # target a specific `adb devices` serial
//
// adb is resolved from ANDROID_HOME / ANDROID_SDK_ROOT / the Android
// project's local.properties, in that order, then from PATH.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { fail, repositoryDirectory } from './lib/repo.mjs';

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    shell: process.platform === 'win32',
    ...options,
  });
  if (result.error) {
    fail(`failed to run ${command}: ${result.error.message}`);
  }
  return result;
}

function parseArgs(argv) {
  const options = { serial: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '-s' || arg === '--serial') {
      const value = argv[index + 1];
      if (!value) fail(`missing value for ${arg}`);
      options.serial = value;
      index += 1;
    } else {
      fail(`unknown argument: ${arg} (only -s <serial> is supported)`);
    }
  }
  return options;
}

function findAdb() {
  const candidates = [];
  for (const variable of ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    if (process.env[variable]) {
      candidates.push(join(process.env[variable], 'platform-tools', 'adb'));
    }
  }
  const localProperties = join(
    repositoryDirectory,
    'app/androidApp/local.properties',
  );
  if (existsSync(localProperties)) {
    const match = readFileSync(localProperties, 'utf8').match(
      /^sdk\.dir=(.+)$/m,
    );
    if (match) candidates.push(join(match[1].trim(), 'platform-tools', 'adb'));
  }
  candidates.push('adb');
  for (const candidate of candidates) {
    if (candidate === 'adb' || existsSync(candidate)) return candidate;
  }
  return fail(
    'adb not found; set ANDROID_HOME or create app/androidApp/local.properties',
  );
}

// `adb devices` prints "serial<TAB>state" per line; only "device" is usable.
function listDevices(adb) {
  const output = run(adb, ['devices']).stdout;
  return output
    .split('\n')
    .slice(1)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => {
      const [serial, state] = line.split(/\s+/);
      return { serial, state };
    });
}

function pickDevice(devices, serial) {
  if (serial) {
    const match = devices.find((device) => device.serial === serial);
    if (!match) fail(`device ${serial} is not connected`);
    if (match.state !== 'device') {
      fail(`device ${serial} is ${match.state}; authorize/unlock it first`);
    }
    return serial;
  }
  const usable = devices.filter((device) => device.state === 'device');
  if (usable.length === 0) {
    fail('no connected devices; plug one in or enable wireless debugging');
  }
  if (usable.length > 1) {
    const lines = usable.map((device) => `  -s ${device.serial}`).join('\n');
    fail(`multiple devices connected, pick one:\n${lines}`);
  }
  return usable[0].serial;
}

// Debug installs use bundleId + debugApplicationIdSuffix from
// package.json#nativeApp, the same source apply-native-config.mjs writes into
// the Gradle project, so scaffolded apps work without edits.
function debugApplicationId() {
  const pkg = JSON.parse(
    readFileSync(join(repositoryDirectory, 'package.json'), 'utf8'),
  );
  const nativeApp = pkg.nativeApp ?? {};
  const bundleId = nativeApp.bundleId;
  const suffix = nativeApp.android?.debugApplicationIdSuffix ?? '';
  if (!bundleId) fail('package.json#nativeApp.bundleId is missing');
  if (suffix.length === 0) return bundleId;
  return `${bundleId}${suffix.startsWith('.') ? suffix : `.${suffix}`}`;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const adb = findAdb();
  const serial = pickDevice(listDevices(adb), options.serial);
  const applicationId = debugApplicationId();

  console.info(`==> Building Android Debug (bundled assets + APK)`);
  const build = run('pnpm', ['run', 'build:androidDebug'], {
    stdio: 'inherit',
  });
  if (build.status !== 0) fail('build failed');

  const apk = join(
    repositoryDirectory,
    'app/androidApp/app/build/outputs/apk/debug/app-debug.apk',
  );
  if (!existsSync(apk)) fail(`APK not found at ${apk}`);

  console.info(`==> Installing ${applicationId} on ${serial}`);
  const install = run(adb, ['-s', serial, 'install', '-r', apk], {
    stdio: 'inherit',
  });
  if (install.status !== 0) fail('install failed');

  // Resolve the launcher activity instead of hardcoding it, so renamed or
  // scaffolded activities keep working. Output ends with "<pkg>/<component>".
  const resolved = run(adb, [
    '-s',
    serial,
    'shell',
    'cmd',
    'package',
    'resolve-activity',
    '--brief',
    '-c',
    'android.intent.category.LAUNCHER',
    applicationId,
  ]);
  if (resolved.status !== 0) fail('failed to resolve launcher activity');
  const component = resolved.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.includes('/'))
    .pop();
  if (!component) fail('could not parse launcher activity');

  console.info(`==> Starting ${component}`);
  const start = run(
    adb,
    ['-s', serial, 'shell', 'am', 'start', '-n', component],
    {
      stdio: 'inherit',
    },
  );
  if (start.status !== 0) fail('start failed');

  console.info(`\nApp is running. Useful commands:`);
  console.info(`  ${adb} -s ${serial} logcat -s LynxTemplateRender lynx`);
  console.info(`  ${adb} -s ${serial} shell am force-stop ${applicationId}`);
}

main();
