import { DeepLinkResolution } from './DeepLinkRouteResolver';

export type DeepLinkHandler = (resolution: DeepLinkResolution) => void;

/**
 * Hands deep link resolutions from the EntryAbility Want lifecycle to the
 * Index page. A cold-start link (onCreate) has no page yet, so it is parked
 * as pending and consumed when Index first appears. A warm link (onNewWant)
 * is delivered to the registered handler, which pushes the page onto the
 * Navigation stack; without a handler it parks for the next cold start.
 */
export class StartupRoute {
  private static pending: DeepLinkResolution | null = null;
  private static handler: DeepLinkHandler | undefined = undefined;

  static deliver(resolution: DeepLinkResolution): void {
    if (StartupRoute.handler !== undefined) {
      StartupRoute.handler(resolution);
    } else {
      StartupRoute.pending = resolution;
    }
  }

  static consumePending(): DeepLinkResolution | null {
    const pending: DeepLinkResolution | null = StartupRoute.pending;
    StartupRoute.pending = null;
    return pending;
  }

  static registerHandler(handler: DeepLinkHandler | undefined): void {
    StartupRoute.handler = handler;
  }
}
