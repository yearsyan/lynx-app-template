import { createHash } from 'node:crypto';
import {
  copyFile,
  mkdir,
  readdir,
  readFile,
  writeFile,
} from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryDirectory = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '..',
);
const workspaceDirectory = join(repositoryDirectory, 'bundle');
const engineVersion = '3.9';
const sdkVersion = '4.0.0';

const nativeTargets = [
  join(repositoryDirectory, 'app/androidApp/app/src/main/assets'),
  join(repositoryDirectory, 'app/iosApp'),
  join(repositoryDirectory, 'app/harmonyApp/entry/src/main/resources/rawfile'),
];

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

const artifactDirectory = join(workspaceDirectory, 'artifacts/latest');
await mkdir(artifactDirectory, { recursive: true });
await writeFile(join(artifactDirectory, 'manifest.json'), serializedManifest);

for (const bundle of bundles) {
  await copyFile(bundle.source, join(artifactDirectory, bundle.url));
}

for (const target of nativeTargets) {
  await mkdir(target, { recursive: true });
  await writeFile(join(target, 'lynx-bundles.json'), serializedManifest);
  for (const bundle of bundles) {
    await copyFile(bundle.source, join(target, bundle.url));
  }
}

console.info(
  `Synced ${bundles.length} bundle(s) to artifacts and ${nativeTargets.length} native projects.`,
);
