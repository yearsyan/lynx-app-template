import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { DownloadManagerModule } from './DownloadManagerModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(DownloadManagerModule.NAME, { moduleClass: DownloadManagerModule });
  }
}
