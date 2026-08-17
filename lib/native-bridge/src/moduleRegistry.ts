import type {
  NativeModuleName,
  NativeModuleRegistry,
} from '@lynx-app/native-contracts';

/** Resolve one host module through the generated registry contract. */
export function requireNativeModule<Name extends NativeModuleName>(
  name: Name,
): NonNullable<NativeModuleRegistry[Name]> {
  'background only';
  const module = (NativeModules as NativeModuleRegistry)[name];
  if (module === undefined) {
    throw new Error(`${name} is not registered by the host`);
  }
  return module as NonNullable<NativeModuleRegistry[Name]>;
}
