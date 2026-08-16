import { useEffect, useState } from '@lynx-js/react';

export type PlatformToastType = 'info' | 'success' | 'error';

export interface PlatformToastOptions {
  type?: PlatformToastType;
  /** Defaults to 2000ms. */
  durationMs?: number;
}

interface ToastItem {
  id: number;
  message: string;
  type: PlatformToastType;
}

const DEFAULT_DURATION_MS = 2000;

// The store lives on the background thread; ToastHost mirrors it into React
// state. A new toast replaces the current one instead of queueing.
let current: ToastItem | null = null;
let nextId = 0;
let dismissTimer: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<() => void>();

function emit() {
  'background only';
  for (const listener of listeners) {
    listener();
  }
}

function show(message: string, options: PlatformToastOptions = {}) {
  'background only';
  if (dismissTimer !== undefined) {
    clearTimeout(dismissTimer);
  }
  current = { id: nextId, message, type: options.type ?? 'info' };
  nextId += 1;
  emit();
  dismissTimer = setTimeout(() => {
    current = null;
    dismissTimer = undefined;
    emit();
  }, options.durationMs ?? DEFAULT_DURATION_MS);
}

/** Lightweight in-page toast; renders through the nearest <ToastHost />. */
export const platformToast = {
  show,
  info(message: string, options: PlatformToastOptions = {}) {
    'background only';
    show(message, { ...options, type: 'info' });
  },
  success(message: string, options: PlatformToastOptions = {}) {
    'background only';
    show(message, { ...options, type: 'success' });
  },
  error(message: string, options: PlatformToastOptions = {}) {
    'background only';
    show(message, { ...options, type: 'error' });
  },
};

const TOAST_GLYPHS: Record<PlatformToastType, string> = {
  info: 'i',
  success: '✓',
  error: '✕',
};

/** Mount once near the app root; toasts float above the page via `fixed`. */
export function ToastHost() {
  const [toast, setToast] = useState<ToastItem | null>(current);

  useEffect(() => {
    const listener = () => {
      'background only';
      setToast(current);
    };
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }, []);

  if (toast === null) {
    return null;
  }

  return (
    <view
      key={toast.id}
      className={`PlatformToast PlatformToast--${toast.type}`}
    >
      <text
        className={`PlatformToast__glyph PlatformToast__glyph--${toast.type}`}
      >
        {TOAST_GLYPHS[toast.type]}
      </text>
      <text className="PlatformToast__message">{toast.message}</text>
    </view>
  );
}
