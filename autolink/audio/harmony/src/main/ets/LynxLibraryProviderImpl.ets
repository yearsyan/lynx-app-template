import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { AudioModule } from './AudioModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(AudioModule.NAME, { moduleClass: AudioModule });
  }
}
