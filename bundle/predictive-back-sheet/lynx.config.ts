import { pluginQRCode } from '@lynx-js/qrcode-rsbuild-plugin';
import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
import { defineConfig } from '@lynx-js/rspeedy';
import { pluginTypeCheck } from '@rsbuild/plugin-type-check';

export default defineConfig({
  output: {
    dataUriLimit: Number.MAX_SAFE_INTEGER,
    inlineScripts: true,
  },
  plugins: [
    pluginQRCode({ schema: (url) => `${url}?fullscreen=true` }),
    pluginReactLynx({ engineVersion: '3.9' }),
    pluginTypeCheck(),
  ],
});
