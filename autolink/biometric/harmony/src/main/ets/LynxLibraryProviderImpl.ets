import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { BiometricModule } from './BiometricModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(BiometricModule.NAME, { moduleClass: BiometricModule });
  }
}
