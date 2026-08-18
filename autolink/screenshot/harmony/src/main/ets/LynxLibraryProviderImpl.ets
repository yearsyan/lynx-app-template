import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ScreenshotModule } from './ScreenshotModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ScreenshotModule.NAME, { moduleClass: ScreenshotModule });
  }
}
