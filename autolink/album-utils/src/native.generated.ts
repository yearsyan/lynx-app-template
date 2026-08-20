// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { AlbumUtils as RawAlbumUtilsModule } from '../types/platform-native-module.js';

export type AlbumUtilsModule = RawAlbumUtilsModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    AlbumUtils?: RawAlbumUtilsModule;
  }
}

/** Name the native hosts register this module under. */
export const ALBUM_UTILS_MODULE_NAME = 'AlbumUtils' as const;
