import { Behavior, LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { NavigationModule } from './NavigationModule';
import { PredictiveBackOverlayUI } from './PredictiveBackOverlayUI';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(NavigationModule.NAME, { moduleClass: NavigationModule });
    registry.registerBehavior(
      PredictiveBackOverlayUI.NAME,
      new Behavior(PredictiveBackOverlayUI as Function),
    );
  }
}
