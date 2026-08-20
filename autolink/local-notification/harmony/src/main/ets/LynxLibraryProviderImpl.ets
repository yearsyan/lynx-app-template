import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { LocalNotificationModule } from './LocalNotificationModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(LocalNotificationModule.NAME, { moduleClass: LocalNotificationModule });
  }
}
