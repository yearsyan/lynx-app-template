import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { RouterModule } from './RouterModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(RouterModule.NAME, { moduleClass: RouterModule });
  }
}
