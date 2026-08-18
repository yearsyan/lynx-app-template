import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { ToastModule } from './ToastModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(ToastModule.NAME, { moduleClass: ToastModule });
  }
}
