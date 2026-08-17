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

test.before(async () => {
  await execFileAsync(process.execPath, ['scripts/export-template.mjs'], {
    cwd: repositoryDirectory,
  });
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
      ['scripts/apply_native_config.mjs', '--check'],
      { cwd: projectDirectory },
    );
    await execFileAsync(
      process.execPath,
      ['scripts/generate-native-contracts.mjs', '--check'],
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
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

for (const platform of Object.keys(platformFixtures)) {
  test(`${platform}-only scaffolds keep later native scripts platform-aware`, () =>
    verifySinglePlatformScaffold(platform));
}
