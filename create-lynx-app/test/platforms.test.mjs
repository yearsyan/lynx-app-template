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
    ]).map((module) => module.name);
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
    const sync = await execFileAsync(
      process.execPath,
      ['scripts/sync-native.mjs'],
      { cwd: projectDirectory },
    );
    assert.match(
      sync.stdout,
      new RegExp(`1 native project\\(s\\): ${platform}`),
    );
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
      fixtureTokens({ autolinkModules: ['mmkv'] }),
    );
    const packageJson = JSON.parse(
      await readFile(join(projectDirectory, 'package.json'), 'utf8'),
    );
    const expected = ['mmkv', 'router', 'webview-bridge'];
    assert.deepEqual(packageJson.nativeApp.autolinkModules, expected);
    assert.deepEqual(
      directAutolinkDependencies(packageJson),
      expectedPackageNames(expected),
    );

    // Every Autolink package resolves its own NativeModule through generated
    // code; generated apps must not retain the former central runtime package.
    await doesNotExist(join(projectDirectory, 'lib/native-runtime'));
    await doesNotExist(join(projectDirectory, 'lib/native-contracts'));
    await doesNotExist(join(projectDirectory, 'lib/webview-bridge'));
    const mmkvPackageJson = JSON.parse(
      await readFile(
        join(projectDirectory, 'autolink/mmkv/package.json'),
        'utf8',
      ),
    );
    assert.equal(mmkvPackageJson.dependencies, undefined);
    const mmkvBridge = await readFile(
      join(projectDirectory, 'autolink/mmkv/src/bridge.generated.ts'),
      'utf8',
    );
    assert.match(mmkvBridge, /NativeModules\[KV_MODULE_NAME\]/);
    assert.doesNotMatch(mmkvBridge, /native-runtime/);
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
    const webviewContracts = await readFile(
      join(
        projectDirectory,
        'autolink/webview-bridge/src/contracts.generated.ts',
      ),
      'utf8',
    );
    assert.match(webviewContracts, /NATIVE_MODULE_METHODS/);
    assert.doesNotMatch(webviewContracts, /\bimport\b/);
    for (const moduleName of ['battery', 'local-notification', 'permissions']) {
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

test('Harmony-only none selection retains Router but not WebView bridge', async () => {
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
    assert.deepEqual(packageJson.nativeApp.autolinkModules, ['router']);
    assert.deepEqual(directAutolinkDependencies(packageJson), [
      '@fixture/autolink-router',
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
