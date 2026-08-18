import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ScannerModule } from './ScannerModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ScannerModule.NAME, { moduleClass: ScannerModule });
  }
}
