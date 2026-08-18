import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ClipboardModule } from './ClipboardModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ClipboardModule.NAME, { moduleClass: ClipboardModule });
  }
}
