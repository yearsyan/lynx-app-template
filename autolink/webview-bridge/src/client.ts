/**
 * Browser-side client for the autolinked `<module-webview>` element.
 *
 * Every host app (Android, iOS, HarmonyOS) replaces or supplements the stock
 * webview implementation with one whose service injects
 * `window.__lynxNativeBridge` into pages loaded inside the element. Every
 * native module registered on the owning LynxView (autolink libraries plus
 * app modules) becomes callable only when named in the element's explicit
 * `params['module-bridge'].modules` capability list. Calls
 * dispatch on the host's Lynx thread, like template JS calling
 * `NativeModules` — the page simply talks to the same modules from the
 * outside.
 *
 * On platforms without the bridge (stock WebView hosts, plain
 * browsers), {@link isNativeBridgeAvailable} reports false and every facade
 * below rejects with `NativeBridgeUnavailableError`.
 */

import type { StatusBarStyle } from '@lynx-app/native-host';
import type { DeviceInfo } from '@lynx-template/autolink-device-info';
import type { HapticImpact } from '@lynx-template/autolink-haptics';
import {
  NATIVE_MODULE_METHODS,
  NATIVE_MODULE_NAMES,
  type NativeMethodName,
  type NativeModuleName,
} from './contracts.generated.js';

interface NativeBridgeGlobal {
  invoke(module: string, method: string, args?: unknown[]): Promise<unknown[]>;
}

declare global {
  interface Window {
    __lynxNativeBridge?: NativeBridgeGlobal;
  }
}

type NativeInvocation = {
  [Name in NativeModuleName]: [
    module: Name,
    method: NativeMethodName<Name>,
    args?: unknown[],
  ];
}[NativeModuleName];

/** Raised when the bridge rejects a call (unexposed/unknown module, …). */
export class NativeBridgeError extends Error {}

/** Raised when the page has no `window.__lynxNativeBridge` at all. */
export class NativeBridgeUnavailableError extends NativeBridgeError {
  constructor() {
    super(
      'window.__lynxNativeBridge is unavailable; the webview host did not ' +
        'enable the module bridge for this document',
    );
    this.name = 'NativeBridgeUnavailableError';
  }
}

export function isNativeBridgeAvailable(): boolean {
  return typeof window !== 'undefined' && window.__lynxNativeBridge != null;
}

/**
 * Generic escape hatch: calls `module.method(...args)` on the host and
 * resolves with the module callback's arguments (empty when the module has
 * no result). Prefer the typed facades below.
 */
export async function invokeNative<T extends unknown[] = unknown[]>(
  ...[module, method, args = []]: NativeInvocation
): Promise<T> {
  const bridge = window.__lynxNativeBridge;
  if (bridge == null) {
    throw new NativeBridgeUnavailableError();
  }
  try {
    return (await bridge.invoke(module, method, args)) as T;
  } catch (error) {
    if (error instanceof NativeBridgeError) {
      throw error;
    }
    const message = error instanceof Error ? error.message : String(error);
    throw new NativeBridgeError(message);
  }
}

async function invokeVoid(...invocation: NativeInvocation): Promise<void> {
  const [error] = await invokeNative<[unknown]>(...invocation);
  if (typeof error === 'string' && error.length > 0) {
    throw new NativeBridgeError(error);
  }
}

/** KV module (MMKV-backed), mirroring the Autolink MMKV package's `kv`. */
export const kv = {
  async setString(key: string, value: string): Promise<void> {
    await invokeVoid(
      NATIVE_MODULE_NAMES.KV,
      NATIVE_MODULE_METHODS.KV.setString,
      [key, value],
    );
  },

  async getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    const [value] = await invokeNative<[string | null]>(
      NATIVE_MODULE_NAMES.KV,
      NATIVE_MODULE_METHODS.KV.getString,
      [key, defaultValue],
    );
    return value ?? null;
  },

  async remove(key: string): Promise<void> {
    await invokeVoid(NATIVE_MODULE_NAMES.KV, NATIVE_MODULE_METHODS.KV.remove, [
      key,
    ]);
  },

  async clear(): Promise<void> {
    await invokeVoid(
      NATIVE_MODULE_NAMES.KV,
      NATIVE_MODULE_METHODS.KV.clear,
      [],
    );
  },

  async contains(key: string): Promise<boolean> {
    const [contains] = await invokeNative<[boolean]>(
      NATIVE_MODULE_NAMES.KV,
      NATIVE_MODULE_METHODS.KV.contains,
      [key],
    );
    return contains === true;
  },

  async setJSON(key: string, value: unknown): Promise<void> {
    await this.setString(key, JSON.stringify(value));
  },

  async getJSON<T>(key: string, defaultValue: T): Promise<T> {
    const serialized = await this.getString(key);
    if (serialized === null) {
      return defaultValue;
    }
    try {
      return JSON.parse(serialized) as T;
    } catch {
      return defaultValue;
    }
  },
};

/** Clipboard module, mirroring the Autolink Clipboard package facade. */
export const clipboard = {
  async setString(text: string): Promise<void> {
    await invokeVoid(
      NATIVE_MODULE_NAMES.Clipboard,
      NATIVE_MODULE_METHODS.Clipboard.setString,
      [text],
    );
  },

  async getString(): Promise<string | null> {
    const [text] = await invokeNative<[string | null]>(
      NATIVE_MODULE_NAMES.Clipboard,
      NATIVE_MODULE_METHODS.Clipboard.getString,
      [],
    );
    return typeof text === 'string' ? text : null;
  },
};

/** Haptics module, mirroring the Autolink Haptics package facade. */
export const haptics = {
  async impact(style: HapticImpact): Promise<void> {
    await invokeVoid(
      NATIVE_MODULE_NAMES.Haptics,
      NATIVE_MODULE_METHODS.Haptics.impact,
      [style],
    );
  },
};

/** StatusBar module, mirroring `@lynx-app/native-host`'s `statusBar`. */
export const statusBar = {
  async setStyle(style: StatusBarStyle): Promise<void> {
    await invokeVoid(
      NATIVE_MODULE_NAMES.StatusBar,
      NATIVE_MODULE_METHODS.StatusBar.setStyle,
      [style],
    );
  },
};

/**
 * DeviceInfo module. Accepts either a structured bridge result or the legacy
 * JSON envelope, matching the Autolink package facade.
 */
export async function getDeviceInfo(): Promise<DeviceInfo> {
  const [payload] = await invokeNative<[unknown]>(
    NATIVE_MODULE_NAMES.DeviceInfo,
    NATIVE_MODULE_METHODS.DeviceInfo.getInfo,
    [],
  );
  return decodeDeviceInfo(payload);
}

function decodeDeviceInfo(payload: unknown): DeviceInfo {
  let parsed = payload;
  if (typeof payload === 'string') {
    try {
      parsed = JSON.parse(payload) as unknown;
    } catch {
      throw new NativeBridgeError('DeviceInfo returned invalid JSON');
    }
  }
  if (typeof parsed !== 'object' || parsed === null) {
    throw new NativeBridgeError('DeviceInfo returned an invalid payload');
  }
  const result = parsed as {
    value?: unknown;
    error?: unknown;
  };
  if (typeof result.error === 'string' && result.error.length > 0) {
    throw new NativeBridgeError(result.error);
  }
  const info = result.value as Partial<DeviceInfo> | null | undefined;
  if (typeof info !== 'object' || info === null) {
    throw new NativeBridgeError('DeviceInfo returned an invalid payload');
  }
  if (
    typeof info.model !== 'string' ||
    typeof info.manufacturer !== 'string' ||
    typeof info.osVersion !== 'string' ||
    (info.osApiLevel !== null && typeof info.osApiLevel !== 'number') ||
    typeof info.appVersion !== 'string' ||
    typeof info.appBuild !== 'string' ||
    typeof info.density !== 'number' ||
    !Number.isFinite(info.density) ||
    typeof info.locale !== 'string' ||
    typeof info.isTablet !== 'boolean' ||
    typeof info.isFoldable !== 'boolean'
  ) {
    throw new NativeBridgeError('DeviceInfo returned an invalid payload');
  }
  return info as DeviceInfo;
}
