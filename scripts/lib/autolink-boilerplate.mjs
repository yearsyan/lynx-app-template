/**
 * Canonical per-module boilerplate for autolink packages, shared by the
 * scaffold (scripts/create-native-module.mjs) and the re-sync
 * (scripts/sync-native-modules.mjs) so generated files cannot drift apart.
 *
 * Only zero-variance files live here; module-specific sources (Java/ObjC/ETS
 * implementations, podspec, gradle dependencies) stay with the scaffold.
 */

export function harmonyHvigorfile() {
  return `import { harTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: harTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
};
`;
}

export function harmonyBuildProfile() {
  return `{
  "apiType": "stageMode",
  "buildOption": {
    "arkOptions": {
      "byteCodeHar": false,
    },
  },
  "targets": [
    {
      "name": "default",
    },
  ],
}
`;
}

export function harmonyModuleJson(directoryName) {
  return `{
  "module": {
    "name": "autolink_${directoryName.replaceAll('-', '_')}",
    "type": "har",
    "deviceTypes": [
      "default",
      "tablet",
      "2in1"
    ]
  }
}
`;
}

/**
 * Rewrite the value of every `(prefix)"old"(suffix)` match, returning the
 * updated text and the match count so callers can assert the expected shape.
 */
export function rewriteManagedValues(content, pattern, value) {
  let count = 0;
  const updated = content.replace(pattern, (_match, prefix, suffix) => {
    count += 1;
    return `${prefix}${value}${suffix}`;
  });
  return { updated, count };
}

// `"@lynx/lynx"` in oh-package.json5. The closing quote in the pattern keeps
// sibling packages such as `@lynx/lynx_base` from matching.
export const HARMONY_LYNX_DEPENDENCY = /("@lynx\/lynx"\s*:\s*")[^"]*(")/;

// Every org.lynxsdk.lynx Maven coordinate (lynx, lynx-processor,
// xelement-webview, ...) shares package.json#lynx.sdkVersion, except
// servalsvg, which publishes on its own channel and keeps its own version.
export const GRADLE_LYNX_COORDINATE =
  /("org\.lynxsdk\.lynx:(?!servalsvg:)[a-z-]+:)[^"]*(")/g;
