import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import {
  access,
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import {
  applicableAutolinkModules,
  loadAutolinkModules,
} from '../../scripts/lib/autolink-selection.mjs';
import { copyTemplate } from '../src/copy.mjs';

const execFileAsync = promisify(execFile);
const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repositoryDirectory = resolve(packageDirectory, '..');
const templateDirectory = join(packageDirectory, 'template');
const platformFixtures = {
  android: {
    directory: 'app/androidApp',
    buildScript: 'build:androidDebug',
    manifest: 'app/androidApp/app/src/main/assets/lynxbundle/lynx-bundles.json',
  },
  ios: {
    directory: 'app/iosApp',
    buildScript: 'build:iosDebug',
    manifest: 'app/iosApp/lynxbundle/lynx-bundles.json',
  },
  harmony: {
    directory: 'app/harmonyApp',
    buildScript: 'build:harmonyDebug',
    manifest:
      'app/harmonyApp/entry/src/main/resources/rawfile/lynxbundle/lynx-bundles.json',
  },
};
let autolinkModules;

function fixtureTokens(overrides = {}) {
  return {
    name: 'autolink-fixture',
    scope: 'fixture',
    package: 'com.example.autolinkfixture',
    harmonyBundle: 'com.example.autolinkfixture.harmony',
    vendor: 'autolinkfixture',
    appName: 'AutolinkFixture',
    displayName: 'Autolink Fixture',
    platforms: ['android', 'ios', 'harmony'],
    ...overrides,
  };
}

function directAutolinkDependencies(packageJson) {
  return Object.keys(packageJson.devDependencies)
    .filter((name) => name.includes('/autolink-'))
    .sort();
}

function expectedPackageNames(names) {
  return names.map((name) => `@fixture/autolink-${name}`).sort();
}

test.before(async () => {
  await execFileAsync(process.execPath, ['scripts/export-template.mjs'], {
    cwd: repositoryDirectory,
  });
  autolinkModules = await loadAutolinkModules(repositoryDirectory);
});

test('release template excludes local Harmony signing material', async () => {
  const manifest = JSON.parse(
    await readFile(
      join(packageDirectory, 'src/template-manifest.json'),
      'utf8',
    ),
  );
  assert.ok(manifest.excludeNames.includes('.ohos-sign'));
  await doesNotExist(join(templateDirectory, 'app/harmonyApp/.ohos-sign'));
});

test('iOS accelerometer normalizes Core Motion g values to m/s^2', async () => {
  const source = await readFile(
    join(repositoryDirectory, 'autolink/device/ios/src/DeviceModule.m'),
    'utf8',
  );
  assert.match(source, /kStandardGravityMetersPerSecondSquared = 9\.80665/);
  for (const axis of ['x', 'y', 'z']) {
    assert.match(
      source,
      new RegExp(
        `${axis}:data\\.acceleration\\.${axis} \\*\\s+` +
          'kStandardGravityMetersPerSecondSquared',
      ),
    );
  }
});

test('iOS sensor availability returns JSON booleans', async () => {
  const source = await readFile(
    join(repositoryDirectory, 'autolink/device/ios/src/DeviceModule.m'),
    'utf8',
  );
  assert.match(
    source,
    /LynxDeviceBooleanJSON\(BOOL value\)[\s\S]*?@\{ @"value" : @\(value\) \}/,
  );
  for (const availability of [
    'self.motionManager.isAccelerometerAvailable',
    'CLLocationManager.headingAvailable',
    'self.motionManager.isGyroAvailable',
    'self.motionManager.isMagnetometerAvailable',
    'CMAltimeter.isRelativeAltitudeAvailable',
  ]) {
    assert.match(
      source,
      new RegExp(
        `LynxDeviceBooleanJSON\\(\\s*${availability.replaceAll('.', '\\.')}\\s*\\)`,
      ),
    );
  }
  assert.match(
    source,
    /LynxDeviceJSON\(@\{ @"error" : @"Unknown sensor type" \}\)/,
  );
});

async function doesNotExist(path) {
  await assert.rejects(access(path), (error) => error?.code === 'ENOENT');
}

async function createBundleOutputs(projectDirectory) {
  const bundleDirectory = join(projectDirectory, 'bundle');
  for (const entry of await readdir(bundleDirectory, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const packageFile = join(bundleDirectory, entry.name, 'package.json');
    let packageJson;
    try {
      packageJson = JSON.parse(await readFile(packageFile, 'utf8'));
    } catch (error) {
      if (error?.code === 'ENOENT') continue;
      throw error;
    }
    if (packageJson.lynxBundle === undefined) continue;
    const sourceEntry = packageJson.lynxBundle.entry ?? 'main';
    const dist = join(bundleDirectory, entry.name, 'dist');
    await mkdir(dist, { recursive: true });
    await writeFile(join(dist, `${sourceEntry}.lynx.bundle`), entry.name);
  }
}

async function verifySinglePlatformScaffold(platform) {
  const temporaryDirectory = await mkdtemp(
    join(tmpdir(), 'lynx-template-platforms-'),
  );
  const projectDirectory = join(temporaryDirectory, 'fixture');
  try {
    await copyTemplate(templateDirectory, projectDirectory, {
      name: 'platform-fixture',
      scope: 'fixture',
      package: 'com.example.fixture',
      harmonyBundle: 'com.example.fixture.harmony',
      vendor: 'fixture',
      appName: 'PlatformFixture',
      displayName: 'Platform Fixture',
      platforms: [platform],
    });

    const packageJson = JSON.parse(
      await readFile(join(projectDirectory, 'package.json'), 'utf8'),
    );
    assert.deepEqual(packageJson.nativeApp.platforms, [platform]);
    const expectedAutolink = applicableAutolinkModules(autolinkModules, [
      platform,
    ])
      .filter((module) => module.defaultEnabled)
      .map((module) => module.name);
    assert.deepEqual(packageJson.nativeApp.autolinkModules, expectedAutolink);
    assert.deepEqual(
      Object.keys(packageJson.devDependencies)
        .filter((name) => name.includes('/autolink-'))
        .sort(),
      expectedAutolink.map((name) => `@fixture/autolink-${name}`).sort(),
    );
    for (const [candidate, fixture] of Object.entries(platformFixtures)) {
      if (candidate === platform) {
        assert.equal(typeof packageJson.scripts[fixture.buildScript], 'string');
        continue;
      }
      assert.equal(packageJson.scripts[fixture.buildScript], undefined);
      await doesNotExist(join(projectDirectory, fixture.directory));
    }

    // The contracts script imports the `typescript` compiler; link the one
    // from this repository so the fixture needs no full install.
    await mkdir(join(projectDirectory, 'node_modules'), { recursive: true });
    await symlink(
      join(repositoryDirectory, 'node_modules/typescript'),
      join(projectDirectory, 'node_modules/typescript'),
      'dir',
    );

    await execFileAsync(
      process.execPath,
      ['scripts/apply-native-config.mjs', '--check'],
      { cwd: projectDirectory },
    );
    await execFileAsync(
      process.execPath,
      ['scripts/apply-autolink-selection.mjs', '--check'],
      { cwd: projectDirectory },
    );
    await execFileAsync(
      process.execPath,
      ['scripts/generate-native-contracts.mjs', '--check'],
      { cwd: projectDirectory },
    );
    await execFileAsync(
      process.execPath,
      ['scripts/sync-native-modules.mjs', '--check'],
      { cwd: projectDirectory },
    );

    await createBundleOutputs(projectDirectory);
    const nativeBundleDirectory = dirname(
      join(projectDirectory, platformFixtures[platform].manifest),
    );
    const staleNativeBundle = join(
      nativeBundleDirectory,
      'removed.lynx.bundle',
    );
    const staleArtifactBundle = join(
      projectDirectory,
      'bundle/artifacts/latest/removed.lynx.bundle',
    );
    await mkdir(nativeBundleDirectory, { recursive: true });
    await mkdir(dirname(staleArtifactBundle), { recursive: true });
    await writeFile(staleNativeBundle, 'stale');
    await writeFile(staleArtifactBundle, 'stale');
    const sync = await execFileAsync(
      process.execPath,
      ['scripts/sync-native.mjs'],
      { cwd: projectDirectory },
    );
    assert.match(
      sync.stdout,
      new RegExp(`1 native project\\(s\\): ${platform}`),
    );
    await doesNotExist(staleNativeBundle);
    await doesNotExist(staleArtifactBundle);
    await access(join(projectDirectory, platformFixtures[platform].manifest));
    for (const [candidate, fixture] of Object.entries(platformFixtures)) {
      if (candidate !== platform) {
        await doesNotExist(join(projectDirectory, fixture.directory));
      }
    }

    if (platform === 'harmony') {
      await doesNotExist(
        join(projectDirectory, 'app/harmonyApp/oh-package-lock.json5'),
      );
      await doesNotExist(
        join(projectDirectory, 'app/harmonyApp/entry/oh-package-lock.json5'),
      );
    }

    if (platform === 'android') {
      // applicationId and Lynx SDK pins live in the same Gradle file. Changing
      // both in one apply must retain both edits rather than letting the later
      // atomic write restore the earlier value.
      packageJson.nativeApp.bundleId = 'com.example.changed';
      packageJson.lynx.sdkVersion = '9.8.7';
      await writeFile(
        join(projectDirectory, 'package.json'),
        `${JSON.stringify(packageJson, null, 2)}\n`,
      );
      await execFileAsync(
        process.execPath,
        ['scripts/apply-native-config.mjs'],
        { cwd: projectDirectory },
      );
      await execFileAsync(
        process.execPath,
        ['scripts/apply-native-config.mjs', '--check'],
        { cwd: projectDirectory },
      );
      const gradle = await readFile(
        join(projectDirectory, 'app/androidApp/app/build.gradle.kts'),
        'utf8',
      );
      assert.match(gradle, /applicationId = "com\.example\.changed"/);
      assert.match(gradle, /org\.lynxsdk\.lynx:lynx:9\.8\.7/);
    }
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

for (const platform of Object.keys(platformFixtures)) {
  test(`${platform}-only scaffolds keep later native scripts platform-aware`, () =>
    verifySinglePlatformScaffold(platform));
}

test('scaffold writes only selected Autolink packages as direct dependencies', async () => {
  const temporaryDirectory = await mkdtemp(
    join(tmpdir(), 'lynx-template-autolink-'),
  );
  const projectDirectory = join(temporaryDirectory, 'fixture');
  try {
    await copyTemplate(
      templateDirectory,
      projectDirectory,
      fixtureTokens({ autolinkModules: ['storage'] }),
    );
    const packageJson = JSON.parse(
      await readFile(join(projectDirectory, 'package.json'), 'utf8'),
    );
    const expected = ['device', 'navigation', 'storage', 'webview-bridge'];
    assert.deepEqual(packageJson.nativeApp.autolinkModules, expected);
    assert.deepEqual(
      directAutolinkDependencies(packageJson),
      expectedPackageNames(expected),
    );
    await readFile(join(projectDirectory, 'autolink.config.json'), 'utf8');
    await doesNotExist(join(projectDirectory, 'config/autolink-modules.json'));

    // Every Autolink package resolves its own NativeModule through generated
    // code; generated apps must not retain the former central runtime package.
    await doesNotExist(join(projectDirectory, 'lib/native-runtime'));
    await doesNotExist(join(projectDirectory, 'lib/native-contracts'));
    await doesNotExist(join(projectDirectory, 'lib/webview-bridge'));
    await doesNotExist(join(projectDirectory, 'lib/activity-sheet'));
    await doesNotExist(join(projectDirectory, 'bundle/predictive-back-sheet'));
    const storagePackageJson = JSON.parse(
      await readFile(
        join(projectDirectory, 'autolink/storage/package.json'),
        'utf8',
      ),
    );
    assert.equal(storagePackageJson.dependencies, undefined);
    const storageBridge = await readFile(
      join(projectDirectory, 'autolink/storage/src/bridge.generated.ts'),
      'utf8',
    );
    assert.match(storageBridge, /NativeModules\[STORAGE_MODULE_NAME\]/);
    assert.doesNotMatch(storageBridge, /native-runtime/);
    const webviewPackageJson = JSON.parse(
      await readFile(
        join(projectDirectory, 'autolink/webview-bridge/package.json'),
        'utf8',
      ),
    );
    assert.equal(webviewPackageJson.exports['./client'], './src/client.ts');
    const webviewClient = await readFile(
      join(projectDirectory, 'autolink/webview-bridge/src/client.ts'),
      'utf8',
    );
    assert.match(webviewClient, /from '\.\/contracts\.generated\.js'/);
    assert.match(
      webviewClient,
      /NATIVE_MODULE_METHODS\.Device\.setStatusBarStyle/,
    );
    const webviewContracts = await readFile(
      join(
        projectDirectory,
        'autolink/webview-bridge/src/contracts.generated.ts',
      ),
      'utf8',
    );
    assert.match(webviewContracts, /NATIVE_MODULE_METHODS/);
    assert.match(webviewContracts, /setStatusBarStyle/);
    assert.match(webviewContracts, /getSafeAreaInsets/);
    assert.doesNotMatch(webviewContracts, /\bStatusBar:/);
    assert.doesNotMatch(webviewContracts, /\bAppInstaller:/);
    assert.doesNotMatch(webviewContracts, /\bimport\b/);
    const deviceDeclaration = await readFile(
      join(
        projectDirectory,
        'autolink/device/types/platform-native-module.d.ts',
      ),
      'utf8',
    );
    assert.match(deviceDeclaration, /getSafeAreaInsets/);
    assert.match(deviceDeclaration, /setStatusBarStyle/);
    assert.match(deviceDeclaration, /getBatteryInfo/);
    assert.doesNotMatch(deviceDeclaration, /installApp/);
    const appInstallerManifest = await readFile(
      join(
        projectDirectory,
        'autolink/app-installer/android/src/main/AndroidManifest.xml',
      ),
      'utf8',
    );
    assert.match(appInstallerManifest, /REQUEST_INSTALL_PACKAGES/);
    assert.equal(
      packageJson.devDependencies['@fixture/autolink-app-installer'],
      undefined,
    );
    const navigationDeclaration = await readFile(
      join(
        projectDirectory,
        'autolink/navigation/types/platform-native-module.d.ts',
      ),
      'utf8',
    );
    assert.match(navigationDeclaration, /setEnabled/);
    assert.match(navigationDeclaration, /configure/);
    assert.match(navigationDeclaration, /openURL/);
    const navigationPackageJson = JSON.parse(
      await readFile(
        join(projectDirectory, 'autolink/navigation/package.json'),
        'utf8',
      ),
    );
    assert.equal(navigationPackageJson.exports['./react'], './src/react.ts');
    assert.equal(navigationPackageJson.dependencies, undefined);
    const navigationFacade = await readFile(
      join(projectDirectory, 'autolink/navigation/src/index.ts'),
      'utf8',
    );
    assert.doesNotMatch(navigationFacade, /@lynx-js\/react/);
    const navigationReact = await readFile(
      join(projectDirectory, 'autolink/navigation/src/react.ts'),
      'utf8',
    );
    assert.match(navigationReact, /backStack\.addInterceptor/);
    assert.match(navigationReact, /\.\/overlay\.js/);
    const backOverlay = await readFile(
      join(projectDirectory, 'autolink/navigation/src/overlay.tsx'),
      'utf8',
    );
    assert.match(backOverlay, /usePredictiveBackOverlay/);
    assert.match(backOverlay, /PredictiveBackOverlay/);
    assert.match(backOverlay, /animationTargetId/);
    const androidBackElement = await readFile(
      join(
        projectDirectory,
        'autolink/navigation/android/src/main/java/com/example/autolinkfixture/autolink/navigation/PredictiveBackOverlayElement.java',
      ),
      'utf8',
    );
    assert.match(androidBackElement, /predictive-back-overlay/);
    const iosBackElement = await readFile(
      join(
        projectDirectory,
        'autolink/navigation/ios/src/LynxPredictiveBackOverlay.m',
      ),
      'utf8',
    );
    assert.match(iosBackElement, /predictive-back-overlay/);
    const harmonyBackProvider = await readFile(
      join(
        projectDirectory,
        'autolink/navigation/harmony/src/main/ets/LynxLibraryProviderImpl.ets',
      ),
      'utf8',
    );
    assert.match(harmonyBackProvider, /PredictiveBackOverlayUI/);
    await doesNotExist(join(projectDirectory, 'lib/native-host'));
    await doesNotExist(
      join(
        projectDirectory,
        'app/androidApp/app/src/main/java/com/lynxapp/nativemodule/StatusBarModule.kt',
      ),
    );
    await doesNotExist(
      join(
        projectDirectory,
        'app/iosApp/iosApp/NativeModules/StatusBarModule.swift',
      ),
    );
    await doesNotExist(
      join(
        projectDirectory,
        'app/androidApp/app/src/main/java/com/lynxapp/nativemodule/BackModule.kt',
      ),
    );
    await doesNotExist(
      join(
        projectDirectory,
        'app/iosApp/iosApp/NativeModules/BackModule.swift',
      ),
    );
    await doesNotExist(
      join(
        projectDirectory,
        'app/harmonyApp/entry/src/main/ets/native/BackModule.ets',
      ),
    );
    await doesNotExist(
      join(
        projectDirectory,
        'app/harmonyApp/entry/src/main/ets/native/StatusBarModule.ets',
      ),
    );
    for (const moduleName of ['local-notification', 'permissions']) {
      const structuredBridge = await readFile(
        join(
          projectDirectory,
          'autolink',
          moduleName,
          'src/bridge.generated.ts',
        ),
        'utf8',
      );
      assert.match(structuredBridge, /validateNativeEnvelope/);
      assert.doesNotMatch(structuredBridge, /JSON\.|decodeNative/);
    }

    // Selection controls native discovery, not source retention: a generated
    // project can enable another module later without re-scaffolding.
    await readFile(
      join(projectDirectory, 'autolink', 'scanner', 'lynx.lib.json'),
      'utf8',
    );
    await execFileAsync(
      process.execPath,
      ['scripts/apply-autolink-selection.mjs', '--check'],
      { cwd: projectDirectory },
    );
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test('Harmony-only none selection retains Navigation but not WebView bridge', async () => {
  const temporaryDirectory = await mkdtemp(
    join(tmpdir(), 'lynx-template-autolink-harmony-'),
  );
  const projectDirectory = join(temporaryDirectory, 'fixture');
  try {
    await copyTemplate(
      templateDirectory,
      projectDirectory,
      fixtureTokens({
        platforms: ['harmony'],
        autolinkModules: ['none'],
      }),
    );
    const packageJson = JSON.parse(
      await readFile(join(projectDirectory, 'package.json'), 'utf8'),
    );
    assert.deepEqual(packageJson.nativeApp.autolinkModules, [
      'device',
      'navigation',
    ]);
    assert.deepEqual(directAutolinkDependencies(packageJson), [
      '@fixture/autolink-device',
      '@fixture/autolink-navigation',
    ]);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test('new NativeModule scaffolds a package-local generated bridge', async () => {
  const temporaryDirectory = await mkdtemp(
    join(tmpdir(), 'lynx-template-new-native-module-'),
  );
  const projectDirectory = join(temporaryDirectory, 'fixture');
  try {
    await copyTemplate(templateDirectory, projectDirectory, fixtureTokens());
    await mkdir(join(projectDirectory, 'node_modules'), { recursive: true });
    await symlink(
      join(repositoryDirectory, 'node_modules/typescript'),
      join(projectDirectory, 'node_modules/typescript'),
      'dir',
    );

    await execFileAsync(
      process.execPath,
      ['scripts/create-native-module.mjs', 'echo-sample'],
      { cwd: projectDirectory },
    );

    const packageJson = JSON.parse(
      await readFile(
        join(projectDirectory, 'autolink/echo-sample/package.json'),
        'utf8',
      ),
    );
    assert.equal(packageJson.dependencies, undefined);
    assert.equal(packageJson.exports['./raw'], './src/native.generated.ts');
    const bridge = await readFile(
      join(projectDirectory, 'autolink/echo-sample/src/bridge.generated.ts'),
      'utf8',
    );
    assert.match(bridge, /NativeModules\[ECHO_SAMPLE_MODULE_NAME\]/);
    assert.doesNotMatch(bridge, /native-runtime/);
    assert.doesNotMatch(bridge, /JSON\.|decodeNative/);
    const facade = await readFile(
      join(projectDirectory, 'autolink/echo-sample/src/index.ts'),
      'utf8',
    );
    assert.match(facade, /from '\.\/bridge\.generated\.js'/);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
