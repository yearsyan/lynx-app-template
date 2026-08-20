import { Behavior, LynxLibraryProvider, LynxLibraryRegistry } from '@lynx/lynx';
import { PressableViewUI } from './PressableViewUI';

/** Registers `<pressable-view>` with Lynx's global HarmonyOS registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerBehavior(
      PressableViewUI.NAME,
      new Behavior(PressableViewUI as Function),
    );
  }
}
