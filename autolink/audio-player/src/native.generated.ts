// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { AudioPlayer as RawAudioPlayerModule } from '../types/platform-native-module.js';

export type AudioPlayerModule = RawAudioPlayerModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    AudioPlayer?: RawAudioPlayerModule;
  }
}

/** Name the native hosts register this module under. */
export const AUDIO_PLAYER_MODULE_NAME = 'AudioPlayer' as const;
