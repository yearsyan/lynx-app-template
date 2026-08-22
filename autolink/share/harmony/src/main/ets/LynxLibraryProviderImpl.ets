import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ShareModule } from './ShareModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ShareModule.NAME, { moduleClass: ShareModule });
  }
}
