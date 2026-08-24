import * as hvigorApi from '@ohos/hvigor';
import { enableHarmonyLynxAutolink } from './vendor/lynx-library-plugin';

enableHarmonyLynxAutolink(hvigorApi, { moduleName: 'entry' });

const HAP_PLUGIN_ID = 'com.ohos.hap';
const DEVTOOL_PACKAGES = [
  '@lynx/lynx_devtool',
  '@lynx/lynx_devtool_service',
];

// HarmonyOS has no Gradle-style debugImplementation declaration. Mutate the
// evaluated HAP model instead, so ohpm/Hvigor only sees DevTool as an entry
// dependency while building the debug mode. The packages deliberately share
// the @lynx/lynx version, matching the SDK-wide pin in the project overrides.
hvigorApi.hvigor.afterNodeEvaluate((node) => {
  if (node.getNodeName() !== 'entry') {
    return;
  }
  const context = node.getContext(HAP_PLUGIN_ID);
  if (context === undefined || context === null) {
    throw new Error('Harmony debug DevTool requires entry to use the HAP plugin');
  }
  if (context.getBuildMode() !== 'debug') {
    return;
  }

  const dependencies = { ...(context.getDependenciesOpt() ?? {}) };
  const lynxVersion = dependencies['@lynx/lynx'];
  if (typeof lynxVersion !== 'string' || lynxVersion.length === 0) {
    throw new Error('Harmony debug DevTool requires an @lynx/lynx dependency');
  }
  for (const packageName of DEVTOOL_PACKAGES) {
    dependencies[packageName] = lynxVersion;
  }
  context.setDependenciesOpt(dependencies);
});
