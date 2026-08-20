import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { AudioPlayerModule } from './AudioPlayerModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(AudioPlayerModule.NAME, { moduleClass: AudioPlayerModule });
  }
}
