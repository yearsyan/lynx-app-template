import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { DeviceInfoModule } from './DeviceInfoModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(DeviceInfoModule.NAME, { moduleClass: DeviceInfoModule });
  }
}
