import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ImageToolingModule } from './ImageToolingModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ImageToolingModule.NAME, { moduleClass: ImageToolingModule });
  }
}
