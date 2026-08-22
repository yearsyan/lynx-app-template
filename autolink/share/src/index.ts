/**
 * System share panel provided by the native Share module: plain text, links
 * and local files (screenshot, album-picker or FileSystem products) handed
 * to the platform's share sheet — Android's chooser, iOS's
 * UIActivityViewController and HarmonyOS's Share Kit panel.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

/**
 * Terminal state of one share request. Codes reachable through normal user
 * flow resolve instead of rejecting so business logic can branch without
 * try/catch; only invalid arguments and host errors reject.
 */
export type ShareOutcomeCode =
  | 'sent'
  | 'dismissed'
  /** A second request while one is already active on this page. */
  | 'busy';

export interface ShareOutcome {
  /** Convenience flag, always `code === 'sent'`. */
  readonly success: boolean;
  readonly code: ShareOutcomeCode;
  /**
   * Target identifier when the platform reports one: the `UIActivityType`
   * string on iOS, the chosen app's package name on Android. HarmonyOS's
   * Share Kit panel reports no target, so it is always `null` there.
   */
  readonly activityType: string | null;
  /** Native diagnostic; intended for logging, not for user display. */
  readonly message: string;
}

export interface ShareOptions {
  /**
   * Subject line for email-like targets and the Share Kit record title.
   * Android also uses it as the chooser dialog title. At most 200
   * characters.
   */
  title?: string;
  /** Plain text payload. At most 10000 characters. */
  text?: string;
  /**
   * Link payload. Must declare a scheme; `javascript:` and `data:` are
   * rejected, matching the `router.openURL` safety rules.
   */
  url?: string;
  /**
   * Local file URIs to share, 1-9 items: `file://` sandbox files (for
   * example `screenshot.capture` or `fileSystem.copyToCache` products) and,
   * on Android, `content://` picker URIs. Remote `http(s)://` files are
   * rejected — download them through the networking layer first.
   */
  files?: string[];
}

/** Normalized request handed to the platform modules. */
export interface ShareRequest {
  title: string | null;
  text: string | null;
  url: string | null;
  files: string[];
}

const SHARE_OUTCOME_CODES: readonly string[] = ['sent', 'dismissed', 'busy'];

const MAX_TITLE_LENGTH = 200;
const MAX_TEXT_LENGTH = 10000;
const MAX_URL_LENGTH = 4096;
const MAX_FILES = 9;
const SCHEME_PATTERN = /^[a-z][a-z0-9+.-]*:/i;
const FORBIDDEN_SCHEMES = /^(?:javascript|data):/i;

interface ShareEnvelope {
  error?: unknown;
  value?: unknown;
}

function requireShareModule() {
  'background only';
  return requireNativeModule();
}

function optionalString(
  value: string | undefined,
  label: string,
  maxLength: number,
): string | null {
  'background only';
  if (value === undefined) {
    return null;
  }
  const normalized = value.trim();
  if (normalized.length === 0) {
    return null;
  }
  if (normalized.length > maxLength) {
    throw new Error(
      `Share ${label} must be at most ${maxLength} characters: ${normalized.length}`,
    );
  }
  return normalized;
}

function normalizeFiles(files: string[] | undefined): string[] {
  'background only';
  if (files === undefined) {
    return [];
  }
  if (!Array.isArray(files)) {
    throw new Error('Share files must be an array of file URIs');
  }
  const normalized: string[] = [];
  for (const entry of files) {
    if (typeof entry !== 'string') {
      throw new Error('Share files must be an array of file URI strings');
    }
    const uri = entry.trim();
    if (uri.length === 0) {
      continue;
    }
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      throw new Error(
        'Share only sends local files; download http(s) files to the cache first',
      );
    }
    if (!uri.startsWith('file://') && !uri.startsWith('content://')) {
      throw new Error(`Share files must be file:// or content:// URIs: ${uri}`);
    }
    if (!normalized.includes(uri)) {
      normalized.push(uri);
    }
  }
  if (normalized.length > MAX_FILES) {
    throw new Error(`Share accepts at most ${MAX_FILES} files`);
  }
  return normalized;
}

function normalizeOptions(options: ShareOptions): ShareRequest {
  'background only';
  if (typeof options !== 'object' || options === null) {
    throw new Error('Share options must be an object');
  }
  const title = optionalString(options.title, 'title', MAX_TITLE_LENGTH);
  const text = optionalString(options.text, 'text', MAX_TEXT_LENGTH);
  let url: string | null = null;
  if (options.url !== undefined) {
    const normalized = options.url.trim();
    if (normalized.length > 0) {
      if (normalized.length > MAX_URL_LENGTH) {
        throw new Error(
          `Share url must be at most ${MAX_URL_LENGTH} characters`,
        );
      }
      if (
        !SCHEME_PATTERN.test(normalized) ||
        FORBIDDEN_SCHEMES.test(normalized)
      ) {
        throw new Error(`Share url must declare a safe scheme: ${normalized}`);
      }
      url = normalized;
    }
  }
  const files = normalizeFiles(options.files);
  if (text === null && url === null && files.length === 0) {
    throw new Error('Share requires a non-empty text, url or files payload');
  }
  return { title, text, url, files };
}

function decodeOutcome(value: unknown): ShareOutcome {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Share returned an invalid outcome');
  }
  const outcome = value as Partial<ShareOutcome>;
  if (
    typeof outcome.code !== 'string' ||
    !SHARE_OUTCOME_CODES.includes(outcome.code)
  ) {
    throw new Error('Share returned an invalid outcome code');
  }
  return {
    success: outcome.code === 'sent',
    code: outcome.code as ShareOutcomeCode,
    activityType:
      outcome.code === 'sent' && typeof outcome.activityType === 'string'
        ? outcome.activityType
        : null,
    message: typeof outcome.message === 'string' ? outcome.message : '',
  };
}

/** System share sheet for text, links and local files. */
export const share = {
  /**
   * Opens the platform's system share panel and resolves with the terminal
   * outcome. User cancellation resolves (`dismissed`) where the platform
   * reports it; only invalid options and host errors reject.
   *
   * Result fidelity differs per platform: iOS reports the real completion
   * and `UIActivityType`; Android reports the chosen target package and a
   * best-effort dismissal when the chooser closes without a pick; HarmonyOS
   * only signals that the panel closed, so it always resolves `sent` with a
   * `null` activityType.
   */
  open(options: ShareOptions): Promise<ShareOutcome> {
    'background only';
    const request = normalizeOptions(options);
    return new Promise((resolve, reject) => {
      try {
        requireShareModule().share(request, (result) => {
          'background only';
          try {
            const envelope = decodeNativeEnvelope(
              result,
              'Share',
            ) as ShareEnvelope;
            if (
              typeof envelope.error === 'string' &&
              envelope.error.length > 0
            ) {
              reject(new Error(envelope.error));
              return;
            }
            resolve(decodeOutcome(envelope.value));
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        });
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  },
};
