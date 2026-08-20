import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { pluginQRCode } from '@lynx-js/qrcode-rsbuild-plugin';
import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
import { defineConfig } from '@lynx-js/rspeedy';
import { pluginTypeCheck } from '@rsbuild/plugin-type-check';

// Plain ESM on purpose: rspeedy imports this package while loading
// lynx.config.ts, where no repository TypeScript transpile step applies.
//
// package.json#lynx.engineVersion is the single source of truth for every
// bundle; apply-native-config.mjs writes the same value into the native
// hosts, so bundles and hosts cannot drift apart.
const rootPackageJson = JSON.parse(
  readFileSync(
    fileURLToPath(new URL('../../../package.json', import.meta.url)),
    'utf8',
  ),
);
const engineVersion = rootPackageJson.lynx?.engineVersion;
if (typeof engineVersion !== 'string' || engineVersion.length === 0) {
  throw new Error('package.json#lynx.engineVersion must be a non-empty string');
}

/** Shared rspeedy config for every workspace bundle (`bundle/*`). */
export function defineBundleConfig() {
  return defineConfig({
    output: {
      // Native hosts and the OTA updater consume one self-contained file.
      dataUriLimit: Number.MAX_SAFE_INTEGER,
      inlineScripts: true,
    },
    plugins: [
      pluginQRCode({
        schema(url) {
          // We use `?fullscreen=true` to open the page in LynxExplorer in full screen mode
          return `${url}?fullscreen=true`;
        },
      }),
      // Must never be greater than the Lynx SDK embedded by the native hosts.
      pluginReactLynx({ engineVersion }),
      pluginTypeCheck(),
    ],
  });
}
