import { pluginQRCode } from '@lynx-js/qrcode-rsbuild-plugin';
import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
import { defineConfig } from '@lynx-js/rspeedy';
import { pluginTypeCheck } from '@rsbuild/plugin-type-check';

export default defineConfig({
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
    pluginReactLynx({ engineVersion: '3.9' }),
    pluginTypeCheck(),
  ],
});
