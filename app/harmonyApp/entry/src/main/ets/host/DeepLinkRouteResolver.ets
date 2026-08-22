import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/** A resolved deep link: the target bundle plus merged route params. */
export interface DeepLinkResolution {
  bundle: string;
  params: Record<string, Object>;
}

class DeepLinkRouteEntry {
  path: string = '';
  bundle: string = '';
  params: Record<string, Object> = {};
}

class DeepLinkConfig {
  schemaVersion: number = 0;
  scheme: string = '';
  host: string = '';
  defaultBundle: string = '';
  routes: DeepLinkRouteEntry[] = [];
}

class ParsedURI {
  scheme: string = '';
  host: string = '';
  path: string = '/';
  query: Record<string, Object> = {};
}

/**
 * Resolves incoming `scheme://host/path?query` deep link URIs against the
 * shared `contracts/deeplinks.json` config, shipped as the rawfile
 * `lynxbundle/deeplinks.json` (see scripts/sync-native.mjs).
 *
 * A URI with a foreign scheme is not a deep link for this app (null). Our
 * scheme with an unknown host or path falls back to the configured default
 * bundle with no params. On a match, route params merge the route's static
 * params with the URL query (query values win).
 */
export class DeepLinkRouteResolver {
  private static readonly CONFIG_RAWFILE_PATH: string = 'lynxbundle/deeplinks.json';
  private static readonly BUNDLE_NAME_PATTERN: RegExp = /^[a-z0-9][a-z0-9-]*$/;
  private static config: DeepLinkConfig | undefined = undefined;

  static resolve(
    context: common.UIAbilityContext,
    uri: string | undefined,
  ): DeepLinkResolution | null {
    if (uri === undefined || uri.length === 0) {
      return null;
    }
    const config: DeepLinkConfig | undefined = DeepLinkRouteResolver.loadConfig(context);
    if (config === undefined) {
      return null;
    }
    const parsed: ParsedURI | null = DeepLinkRouteResolver.parseURI(uri);
    if (parsed === null || parsed.scheme !== config.scheme.toLowerCase()) {
      return null;
    }

    let entry: DeepLinkRouteEntry | undefined = undefined;
    if (parsed.host === config.host.toLowerCase()) {
      for (let index: number = 0; index < config.routes.length; index++) {
        if (config.routes[index].path === parsed.path) {
          entry = config.routes[index];
          break;
        }
      }
    }
    if (entry === undefined) {
      return DeepLinkRouteResolver.BUNDLE_NAME_PATTERN.test(config.defaultBundle)
        ? ({ bundle: config.defaultBundle, params: {} } as DeepLinkResolution)
        : null;
    }
    if (!DeepLinkRouteResolver.BUNDLE_NAME_PATTERN.test(entry.bundle)) {
      return null;
    }

    const params: Record<string, Object> = {};
    const staticKeys: string[] = Object.keys(entry.params);
    for (let index: number = 0; index < staticKeys.length; index++) {
      const key: string = staticKeys[index];
      params[key] = entry.params[key];
    }
    const queryKeys: string[] = Object.keys(parsed.query);
    for (let index: number = 0; index < queryKeys.length; index++) {
      const key: string = queryKeys[index];
      params[key] = parsed.query[key];
    }
    return { bundle: entry.bundle, params } as DeepLinkResolution;
  }

  private static parseURI(uri: string): ParsedURI | null {
    const schemeSeparator: string = '://';
    const schemeIndex: number = uri.indexOf(schemeSeparator);
    if (schemeIndex <= 0) {
      return null;
    }
    const parsed: ParsedURI = new ParsedURI();
    parsed.scheme = uri.substring(0, schemeIndex).toLowerCase();
    let rest: string = uri.substring(schemeIndex + schemeSeparator.length);
    const queryIndex: number = rest.indexOf('?');
    if (queryIndex >= 0) {
      parsed.query = DeepLinkRouteResolver.parseQuery(rest.substring(queryIndex + 1));
      rest = rest.substring(0, queryIndex);
    }
    const pathIndex: number = rest.indexOf('/');
    if (pathIndex < 0) {
      parsed.host = rest.toLowerCase();
    } else {
      parsed.host = rest.substring(0, pathIndex).toLowerCase();
      parsed.path = DeepLinkRouteResolver.normalizePath(rest.substring(pathIndex));
    }
    return parsed;
  }

  private static parseQuery(queryText: string): Record<string, Object> {
    const query: Record<string, Object> = {};
    if (queryText.length === 0) {
      return query;
    }
    const pairs: string[] = queryText.split('&');
    for (let index: number = 0; index < pairs.length; index++) {
      const pair: string = pairs[index];
      if (pair.length === 0) {
        continue;
      }
      const equalIndex: number = pair.indexOf('=');
      const rawKey: string = equalIndex < 0 ? pair : pair.substring(0, equalIndex);
      const rawValue: string = equalIndex < 0 ? '' : pair.substring(equalIndex + 1);
      if (rawKey.length === 0) {
        continue;
      }
      let key: string = rawKey;
      let value: string = rawValue;
      try {
        key = decodeURIComponent(rawKey);
        value = decodeURIComponent(rawValue);
      } catch (error) {
        // Malformed escapes keep their raw form instead of failing the link.
        console.warn(`Deep link query pair is not URI-encoded: ${pair}`);
      }
      query[key] = value;
    }
    return query;
  }

  private static normalizePath(path: string): string {
    if (path.length === 0) {
      return '/';
    }
    let normalized: string = path.startsWith('/') ? path : `/${path}`;
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.length === 0 ? '/' : normalized;
  }

  private static loadConfig(context: common.UIAbilityContext): DeepLinkConfig | undefined {
    if (DeepLinkRouteResolver.config !== undefined) {
      return DeepLinkRouteResolver.config;
    }
    try {
      const content: Uint8Array = context.resourceManager.getRawFileContentSync(
        DeepLinkRouteResolver.CONFIG_RAWFILE_PATH,
      );
      const text: string = util.TextDecoder.create('utf-8').decodeToString(content);
      const config: DeepLinkConfig = JSON.parse(text) as DeepLinkConfig;
      DeepLinkRouteResolver.config = config;
      return config;
    } catch (error) {
      console.error(`Unable to load deep link config: ${error}`);
      return undefined;
    }
  }
}
