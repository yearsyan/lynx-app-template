import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { DisplayModule } from './DisplayModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(DisplayModule.NAME, { moduleClass: DisplayModule });
  }
}
