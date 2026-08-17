export const SUPPORTED_NATIVE_PLATFORMS = Object.freeze([
  'android',
  'ios',
  'harmony',
]);

const supportedPlatforms = new Set(SUPPORTED_NATIVE_PLATFORMS);

function requireRecord(value, location) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${location} must be a JSON object`);
  }
  return value;
}

/**
 * Read the native hosts that belong to this project. The scaffold writes this
 * field before deleting unselected native directories, making it the shared
 * source used by every repository script that touches a native host.
 */
export function enabledNativePlatforms(packageJson) {
  const packageData = requireRecord(packageJson, 'package.json');
  const nativeApp = requireRecord(
    packageData.nativeApp,
    'package.json#nativeApp',
  );
  const platforms = nativeApp.platforms;
  if (!Array.isArray(platforms) || platforms.length === 0) {
    throw new Error(
      'package.json#nativeApp.platforms must be a non-empty array',
    );
  }

  const seen = new Set();
  for (const [index, platform] of platforms.entries()) {
    const location = `package.json#nativeApp.platforms[${index}]`;
    if (typeof platform !== 'string') {
      throw new Error(`${location} must be a string`);
    }
    if (!supportedPlatforms.has(platform)) {
      throw new Error(
        `${location} is not supported: ${JSON.stringify(platform)}`,
      );
    }
    if (seen.has(platform)) {
      throw new Error(`${location} duplicates ${JSON.stringify(platform)}`);
    }
    seen.add(platform);
  }

  return [...platforms];
}
