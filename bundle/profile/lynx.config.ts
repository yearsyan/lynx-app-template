import { pluginQRCode } from '@lynx-js/qrcode-rsbuild-plugin';
import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
import { defineConfig } from '@lynx-js/rspeedy';

export default defineConfig({
  output: { dataUriLimit: Number.MAX_SAFE_INTEGER },
  plugins: [
    pluginQRCode({ schema: (url) => `${url}?fullscreen=true` }),
    pluginReactLynx(),
  ],
});
