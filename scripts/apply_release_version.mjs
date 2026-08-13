import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// npm 官方 semver 校验的一个宽松子集，足够覆盖 `v0.1.2` / `0.1.2-rc.1`。
const SEMVER = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

async function main() {
  const version = process.argv[2];
  if (!version) {
    fail('usage: node scripts/apply_release_version.mjs <semver>');
  }
  if (!SEMVER.test(version)) {
    fail(`invalid semver: ${JSON.stringify(version)}`);
  }

  const packages = [
    {
      path: resolve(repositoryRoot, 'create-lynx-app', 'package.json'),
      update(pkg) {
        pkg.version = version;
      },
    },
    {
      path: resolve(repositoryRoot, 'create-lynx-app-alias', 'package.json'),
      update(pkg) {
        pkg.version = version;
        pkg.dependencies['@lynfe/lynx-app'] = version;
      },
    },
  ];

  for (const pkg of packages) {
    const json = JSON.parse(await readFile(pkg.path, 'utf8'));
    pkg.update(json);
    await writeFile(pkg.path, `${JSON.stringify(json, null, 2)}\n`, 'utf8');
    console.info(`Updated ${pkg.path} to ${version}`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
