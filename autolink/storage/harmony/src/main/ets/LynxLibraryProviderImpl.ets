import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { StorageModule } from './StorageModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(StorageModule.NAME, { moduleClass: StorageModule });
  }
}
