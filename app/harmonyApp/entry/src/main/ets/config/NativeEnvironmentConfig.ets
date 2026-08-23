import { Configuration, ConfigurationConstant } from '@kit.AbilityKit';

export const NATIVE_COLOR_SCHEME_KEY: string = 'lynx.native.colorScheme';
export const NATIVE_LOCALE_KEY: string = 'lynx.native.locale';

export function resolvedColorScheme(configuration: Configuration): string {
  return configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    ? 'dark'
    : 'light';
}

export function resolvedLocale(configuration: Configuration): string {
  return configuration.language ?? 'en';
}
