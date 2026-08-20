// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { FileSystem as RawFileSystemModule } from '../types/platform-native-module.js';

export type FileSystemModule = RawFileSystemModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    FileSystem?: RawFileSystemModule;
  }
}

/** Name the native hosts register this module under. */
export const FILE_SYSTEM_MODULE_NAME = 'FileSystem' as const;
