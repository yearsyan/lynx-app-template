import { stdin as input, stdout as output } from 'node:process';
import readline from 'node:readline/promises';

const KEBAB = /^[a-z0-9][a-z0-9-]*$/;
// Android applicationId rules are the strictest of the three hosts: every
// dot-separated segment starts with a letter and contains only letters,
// digits, and underscores. The same value also feeds iOS and HarmonyOS.
const BUNDLE_ID = /^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/;
const SCOPE = /^[a-z0-9][a-z0-9-]*$/;
const PLATFORMS = new Set(['android', 'ios', 'harmony']);

// Kebab-case names cannot become package segments as-is (no hyphens allowed).
function defaultBundleId(name) {
  return `com.${name.replace(/-/g, '')}`;
}

function kebabToPascalCase(value) {
  return value
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

function kebabToTitleCase(value) {
  return value
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function lastSegment(bundleId) {
  return bundleId.split('.').pop() || 'app';
}

function flagValue(argv, name) {
  const index = argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  const value = argv[index + 1];
  return value && !value.startsWith('--') ? value : undefined;
}

function hasFlag(argv, name) {
  return argv.includes(`--${name}`);
}

function commaList(argv, name) {
  const raw = flagValue(argv, name);
  if (!raw) return undefined;
  return raw
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

async function prompt(rl, question, { validate, fallback } = {}) {
  let value;
  do {
    value = (await rl.question(question)).trim();
    if (value === '') value = fallback ?? '';
    if (validate && !validate(value)) {
      console.error(`  Invalid value: ${JSON.stringify(value)}`);
      value = '';
    }
  } while (value === '' && fallback === undefined);
  return value || fallback || '';
}

export async function resolveOptions(argv) {
  const positional = argv.filter((arg) => !arg.startsWith('--'));
  const name = positional[0];

  if (!name || !KEBAB.test(name)) {
    fail(
      'project name must be kebab-case, e.g. `pnpm dlx @lynfe/lynx-app my-app`',
    );
  }

  const interactive = !hasFlag(argv, 'yes') && process.stdin.isTTY;

  let scope = flagValue(argv, 'scope') ?? 'lynfe';
  let bundleId = flagValue(argv, 'bundle-id');
  let displayName = flagValue(argv, 'display-name');
  let platforms = commaList(argv, 'platforms');

  if (interactive) {
    const rl = readline.createInterface({ input, output });
    try {
      scope = await prompt(rl, `npm scope [${scope}]: `, {
        validate: (v) => SCOPE.test(v),
        fallback: scope,
      });
      bundleId = await prompt(rl, `bundle ID [${defaultBundleId(name)}]: `, {
        validate: (v) => BUNDLE_ID.test(v),
        fallback: bundleId ?? defaultBundleId(name),
      });
      displayName = await prompt(
        rl,
        `display name [${kebabToTitleCase(name)}]: `,
        { fallback: displayName ?? kebabToTitleCase(name) },
      );
      const platformDefault = 'android,ios,harmony';
      platforms = await prompt(
        rl,
        `platforms (comma-separated) [${platformDefault}]: `,
        {
          fallback: platformDefault,
        },
      ).then((value) =>
        value
          .split(',')
          .map((item) => item.trim().toLowerCase())
          .filter(Boolean),
      );
    } finally {
      rl.close();
    }
  }

  bundleId ??= defaultBundleId(name);
  displayName ??= kebabToTitleCase(name);
  platforms ??= ['android', 'ios', 'harmony'];

  if (!SCOPE.test(scope)) fail(`invalid npm scope: ${scope}`);
  if (!BUNDLE_ID.test(bundleId)) {
    fail(
      `invalid bundle ID: ${bundleId} (segments must start with a letter and ` +
        'contain only letters, digits, and underscores)',
    );
  }
  for (const platform of platforms) {
    if (!PLATFORMS.has(platform)) fail(`unknown platform: ${platform}`);
  }
  if (platforms.length === 0) {
    fail('at least one platform must be selected');
  }

  return {
    name,
    scope,
    package: bundleId,
    harmonyBundle: `${bundleId}.harmony`,
    vendor: lastSegment(bundleId),
    appName: kebabToPascalCase(name),
    displayName,
    platforms: [...new Set(platforms)],
  };
}

export { defaultBundleId, kebabToPascalCase, kebabToTitleCase, lastSegment };
