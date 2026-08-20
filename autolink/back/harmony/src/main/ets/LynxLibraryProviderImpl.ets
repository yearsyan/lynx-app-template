import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { BackModule } from './BackModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(BackModule.NAME, { moduleClass: BackModule });
  }
}
