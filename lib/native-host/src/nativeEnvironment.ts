import type { InitData } from '@lynx-js/react';

export interface SafeAreaInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface NativeEnvironment {
  schemaVersion: number;
  /** All native geometry is converted to Lynx logical px before delivery. */
  unit: 'px';
  safeAreaInsets: SafeAreaInsets;
}

declare module '@lynx-js/react' {
  interface InitData {
    nativeEnvironment?: NativeEnvironment;
  }
}

function normalizeInset(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, value)
    : 0;
}

export function readSafeAreaInsets(
  initData: InitData | null | undefined,
): SafeAreaInsets {
  const insets = initData?.nativeEnvironment?.safeAreaInsets;
  return {
    top: normalizeInset(insets?.top),
    right: normalizeInset(insets?.right),
    bottom: normalizeInset(insets?.bottom),
    left: normalizeInset(insets?.left),
  };
}
