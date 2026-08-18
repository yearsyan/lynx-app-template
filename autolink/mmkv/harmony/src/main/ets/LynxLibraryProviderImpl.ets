import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { KVModule } from './KVModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(KVModule.NAME, { moduleClass: KVModule });
  }
}
