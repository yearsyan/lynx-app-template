import { Behavior, LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { BackModule } from './BackModule';
import { PredictiveBackOverlayUI } from './PredictiveBackOverlayUI';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(BackModule.NAME, { moduleClass: BackModule });
    registry.registerBehavior(
      PredictiveBackOverlayUI.NAME,
      new Behavior(PredictiveBackOverlayUI as Function),
    );
  }
}
