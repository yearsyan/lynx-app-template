import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { HapticsModule } from './HapticsModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(HapticsModule.NAME, { moduleClass: HapticsModule });
  }
}
