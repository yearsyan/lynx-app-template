import { StartupConfig, StartupConfigEntry } from '@kit.AbilityKit';

export default class AppStartupConfig extends StartupConfigEntry {
  onConfig(): StartupConfig {
    return { timeoutMs: 10000 };
  }
}
