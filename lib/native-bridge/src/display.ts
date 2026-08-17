/**
 * On-demand display metrics from the native Display module. All widths are
 * Lynx logical pixels (dp/pt/vp) — the unit Lynx layout consumes.
 */

interface DisplayModule {
  screenWidth(callback: (resultJSON: string) => void): void;
  windowWidth(callback: (resultJSON: string) => void): void;
  lynxViewWidth(callback: (resultJSON: string) => void): void;
}

interface AppModules {
  Display?: DisplayModule;
}

interface DisplayWidthResult {
  error?: unknown;
  value?: unknown;
}

function requireDisplayModule(): DisplayModule {
  'background only';
  const module = (NativeModules as AppModules).Display;
  if (module === undefined) {
    throw new Error('Display is not registered by the host');
  }
  return module;
}

function queryWidth(
  label: string,
  action: (
    module: DisplayModule,
    callback: (resultJSON: string) => void,
  ) => void,
): Promise<number> {
  'background only';
  return new Promise((resolve, reject) => {
    action(requireDisplayModule(), (resultJSON) => {
      'background only';
      try {
        if (typeof resultJSON !== 'string') {
          throw new Error(`${label} returned a non-string result`);
        }
        const parsed = JSON.parse(resultJSON) as unknown;
        if (typeof parsed !== 'object' || parsed === null) {
          throw new Error(`${label} returned an invalid result`);
        }
        const result = parsed as DisplayWidthResult;
        if (typeof result.error === 'string' && result.error.length > 0) {
          reject(new Error(result.error));
          return;
        }
        if (
          typeof result.value !== 'number' ||
          !Number.isFinite(result.value)
        ) {
          throw new Error(`${label} returned an invalid width`);
        }
        resolve(result.value);
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  });
}

export const display = {
  /** Full screen width, ignoring multi-window or split-screen sizing. */
  screenWidth(): Promise<number> {
    'background only';
    return queryWidth('Display', (module, callback) =>
      module.screenWidth(callback),
    );
  },

  /** Width of the window the app currently occupies. */
  windowWidth(): Promise<number> {
    'background only';
    return queryWidth('Display', (module, callback) =>
      module.windowWidth(callback),
    );
  },

  /**
   * Width of the LynxView rendering this bundle. Resolves to 0 while the
   * view has not been laid out yet, and rejects when no LynxView is
   * attached (or the host cannot measure it).
   */
  lynxViewWidth(): Promise<number> {
    'background only';
    return queryWidth('Display', (module, callback) =>
      module.lynxViewWidth(callback),
    );
  },
};
