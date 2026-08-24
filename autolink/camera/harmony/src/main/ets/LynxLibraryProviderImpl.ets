import {
  Behavior,
  LynxLibraryProvider,
  LynxLibraryRegistry,
} from '@lynx/lynx';
import { CameraModule } from './CameraModule';
import { CameraViewUI } from './CameraViewUI';

/** Registers this source HAR with Lynx's global HarmonyOS library registry. */
export class LynxLibraryProviderImpl implements LynxLibraryProvider {
  register(registry: LynxLibraryRegistry): void {
    registry.registerModule(CameraModule.NAME, { moduleClass: CameraModule });
    registry.registerBehavior(
      CameraViewUI.NAME,
      new Behavior(CameraViewUI as Function),
    );
  }
}
