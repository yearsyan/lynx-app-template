import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { DeviceModule } from './DeviceModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(DeviceModule.NAME, { moduleClass: DeviceModule });
  }
}
