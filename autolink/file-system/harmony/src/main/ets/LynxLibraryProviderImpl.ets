import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { FileSystemModule } from './FileSystemModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(FileSystemModule.NAME, { moduleClass: FileSystemModule });
  }
}
