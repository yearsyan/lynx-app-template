import { LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { WebSocketModule } from './WebSocketModule';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(WebSocketModule.NAME, { moduleClass: WebSocketModule });
  }
}
