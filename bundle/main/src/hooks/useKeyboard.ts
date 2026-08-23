import { useGlobalEventListener } from '@lynx-js/lynx-ui';
import { useState } from '@lynx-js/react';

export interface KeyboardState {
  readonly visible: boolean;
  /** Keyboard height in logical pixels. Zero while the keyboard is hidden. */
  readonly height: number;
}

const INITIAL_KEYBOARD_STATE: KeyboardState = {
  visible: false,
  height: 0,
};

/** Returns the current software-keyboard visibility and height. */
export function useKeyboard(): KeyboardState {
  const [keyboard, setKeyboard] = useState<KeyboardState>(
    INITIAL_KEYBOARD_STATE,
  );

  useGlobalEventListener(
    'keyboardstatuschanged',
    (status: unknown, height: unknown) => {
      'background only';
      if (status !== 'on' && status !== 'off') return;

      const visible = status === 'on';
      const normalizedHeight =
        visible &&
        typeof height === 'number' &&
        Number.isFinite(height) &&
        height > 0
          ? height
          : 0;

      setKeyboard((current) => {
        if (
          current.visible === visible &&
          current.height === normalizedHeight
        ) {
          return current;
        }
        return { visible, height: normalizedHeight };
      });
    },
    [],
  );

  return keyboard;
}
