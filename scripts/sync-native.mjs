import { createHash } from 'node:crypto';
import {
  access,
  copyFile,
  mkdir,
  readdir,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { join } from 'node:path';

import { enabledNativePlatforms } from './lib/native-platforms.mjs';
import {
  readRootPackageJson,
  repositoryDirectory,
  requireLynxVersion,
} from './lib/repo.mjs';

const workspaceDirectory = join(repositoryDirectory, 'bundle');
const rootPackageJson = await readRootPackageJson();
const enabledPlatforms = enabledNativePlatforms(rootPackageJson);
const engineVersion = requireLynxVersion(rootPackageJson, 'engineVersion');
const sdkVersion = requireLynxVersion(rootPackageJson, 'sdkVersion');

const nativePlatforms = {
  android: {
    root: 'app/androidApp',
    target: 'app/androidApp/app/src/main/assets/lynxbundle',
    legacyTarget: 'app/androidApp/app/src/main/assets',
  },
  ios: {
    root: 'app/iosApp',
    target: 'app/iosApp/lynxbundle',
    legacyTarget: 'app/iosApp',
  },
  harmony: {
    root: 'app/harmonyApp',
    target: 'app/harmonyApp/entry/src/main/resources/rawfile/lynxbundle',
    legacyTarget: 'app/harmonyApp/entry/src/main/resources/rawfile',
  },
};

const nativeTargets = [];
const legacyNativeTargets = [];
for (const platform of enabledPlatforms) {
  const nativePlatform = nativePlatforms[platform];
  const root = join(repositoryDirectory, nativePlatform.root);
  try {
    await access(root);
  } catch {
    throw new Error(
      `Enabled native platform directory is missing: ${nativePlatform.root}`,
    );
  }
  nativeTargets.push(join(repositoryDirectory, nativePlatform.target));
  legacyNativeTargets.push(
    join(repositoryDirectory, nativePlatform.legacyTarget),
  );
}

const entries = await readdir(workspaceDirectory, { withFileTypes: true });
const bundles = [];

for (const entry of entries) {
  if (!entry.isDirectory()) continue;

  const packageFile = join(workspaceDirectory, entry.name, 'package.json');
  let packageJson;
  try {
    packageJson = JSON.parse(await readFile(packageFile, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') continue;
    throw error;
  }

  const bundleConfig = packageJson.lynxBundle;
  if (!bundleConfig) continue;

  const name = bundleConfig.name ?? entry.name;
  const sourceEntry = bundleConfig.entry ?? 'main';
  if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) {
    throw new Error(`Invalid Lynx bundle name: ${name}`);
  }

  const source = join(
    workspaceDirectory,
    entry.name,
    'dist',
    `${sourceEntry}.lynx.bundle`,
  );
  const data = await readFile(source);
  bundles.push({
    name,
    version: packageJson.version,
    url: `${name}.lynx.bundle`,
    sha256: createHash('sha256').update(data).digest('hex'),
    size: data.byteLength,
    source,
  });
}

if (bundles.length === 0) {
  throw new Error('No packages with a lynxBundle field were found');
}

bundles.sort((left, right) => left.name.localeCompare(right.name));

// Deep link config: the single source of truth for the URL prefix and the
// path-to-bundle route table. It ships next to lynx-bundles.json so every
// host reads the same mapping at runtime.
const deepLinkConfigFile = join(
  repositoryDirectory,
  'contracts/deeplinks.json',
);
let deepLinkConfig;
try {
  deepLinkConfig = JSON.parse(await readFile(deepLinkConfigFile, 'utf8'));
} catch (error) {
  throw new Error(`Unable to read ${deepLinkConfigFile}: ${error.message}`);
}
validateDeepLinkConfig(
  deepLinkConfig,
  new Set(bundles.map((bundle) => bundle.name)),
);
const serializedDeepLinkConfig = `${JSON.stringify(deepLinkConfig, null, 2)}\n`;

const sourceDateEpoch = process.env.SOURCE_DATE_EPOCH;
const generatedAt = sourceDateEpoch
  ? new Date(Number(sourceDateEpoch) * 1000).toISOString()
  : new Date().toISOString();
const manifest = {
  schemaVersion: 1,
  engineVersion,
  sdkVersion,
  channel: process.env.LYNX_RELEASE_CHANNEL ?? 'production',
  generatedAt,
  bundles: bundles.map(({ source: _, ...bundle }) => bundle),
};
const serializedManifest = `${JSON.stringify(manifest, null, 2)}\n`;

function validateDeepLinkConfig(config, bundleNames) {
  const file = 'contracts/deeplinks.json';
  const bundleNamePattern = /^[a-z0-9][a-z0-9-]*$/;
  if (config?.schemaVersion !== 1) {
    throw new Error(`${file}: schemaVersion must be 1`);
  }
  if (!/^[a-z][a-z0-9+.-]*$/.test(config.scheme ?? '')) {
    throw new Error(`${file}: scheme must be a lowercase URI scheme`);
  }
  if (!/^[a-z0-9][a-z0-9.-]*$/.test(config.host ?? '')) {
    throw new Error(
      `${file}: host must be a bare lowercase hostname (no scheme, port, or path)`,
    );
  }
  if (
    !bundleNamePattern.test(config.defaultBundle ?? '') ||
    !bundleNames.has(config.defaultBundle)
  ) {
    throw new Error(
      `${file}: defaultBundle "${config.defaultBundle}" is not a known bundle`,
    );
  }
  if (!Array.isArray(config.routes) || config.routes.length === 0) {
    throw new Error(`${file}: routes must be a non-empty array`);
  }
  const paths = new Set();
  for (const route of config.routes) {
    if (
      typeof route?.path !== 'string' ||
      !route.path.startsWith('/') ||
      route.path.includes('?')
    ) {
      throw new Error(
        `${file}: route path "${route?.path}" must start with "/" and carry no query`,
      );
    }
    if (paths.has(route.path)) {
      throw new Error(`${file}: duplicate route path "${route.path}"`);
    }
    paths.add(route.path);
    if (
      !bundleNamePattern.test(route.bundle ?? '') ||
      !bundleNames.has(route.bundle)
    ) {
      throw new Error(
        `${file}: route "${route.path}" maps to unknown bundle "${route?.bundle}"`,
      );
    }
    if (
      route.params !== undefined &&
      (typeof route.params !== 'object' ||
        Array.isArray(route.params) ||
        route.params === null)
    ) {
      throw new Error(
        `${file}: route "${route.path}" params must be a JSON object`,
      );
    }
  }
}

async function clearGeneratedBundles(directory) {
  await mkdir(directory, { recursive: true });
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith('.lynx.bundle')) {
      await rm(join(directory, entry.name), { force: true });
    }
  }
}

const artifactDirectory = join(workspaceDirectory, 'artifacts/latest');
await clearGeneratedBundles(artifactDirectory);
await writeFile(join(artifactDirectory, 'manifest.json'), serializedManifest);

for (const bundle of bundles) {
  await copyFile(bundle.source, join(artifactDirectory, bundle.url));
}

for (const target of nativeTargets) {
  await clearGeneratedBundles(target);
  await writeFile(join(target, 'lynx-bundles.json'), serializedManifest);
  await writeFile(join(target, 'deeplinks.json'), serializedDeepLinkConfig);
  for (const bundle of bundles) {
    await copyFile(bundle.source, join(target, bundle.url));
  }
}

// Remove files generated by releases before native resources used lynxbundle/.
for (const target of legacyNativeTargets) {
  await rm(join(target, 'lynx-bundles.json'), { force: true });
  for (const bundle of bundles) {
    await rm(join(target, bundle.url), { force: true });
  }
}

console.info(
  `Synced ${bundles.length} bundle(s) to artifacts and ${nativeTargets.length} native project(s): ${enabledPlatforms.join(', ')}.`,
);
console.info('Synced contracts/deeplinks.json to the same native project(s).');
